//
//  CoreWrapper.mm
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 09.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreWrapper.h"

#include <odr/document.hpp>
#include <odr/document_element.hpp>
#include <odr/file.hpp>
#include <odr/html.hpp>
#include <odr/http_server.hpp>
#include <odr/odr.hpp>
#include <odr/exceptions.hpp>
#include <odr/global_params.hpp>

#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <optional>
#include <string>
#include <thread>

/// Whether the translated HTML reaches the web view over loopback HTTP instead
/// of being written to the output directory as files.
///
/// HTTP is what OpenDocument.droid does and where this is headed. odrcore then
/// renders a page when the web view asks for it, on one of the server's
/// threads, rather than rendering every page up front on whichever thread
/// called `translate`. Set this to `NO` to go back to files - the offline path
/// is kept working until the migration is finished, not as a runtime option.
static const BOOL kCoreWrapperServesOverHttp = YES;

/// Loopback port for that server, the same one OpenDocument.droid uses.
/// Nothing off the device can reach it: the socket is bound to 127.0.0.1.
static const std::uint32_t kCoreWrapperHttpPort = 29665;

NSErrorDomain const CoreWrapperErrorDomain = @"app.opendocument.CoreWrapperErrorDomain";

static NSError *CoreWrapperMakeError(CoreWrapperError code, NSString *description) {
    return [NSError errorWithDomain:CoreWrapperErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

/// The view odrcore names "document" holds the whole file in one page: every
/// slide of a presentation, every page of a PDF, the entire text document.
static bool CoreWrapperIsCombinedView(const odr::HtmlView &view) {
    return view.name() == "document";
}

/// Picks the views to show as pages, the same way OpenDocument.droid does.
///
/// Spreadsheets get one tab per sheet, because scrolling through every sheet of
/// a workbook in one page is not how anyone reads a spreadsheet. Everything else
/// gets the combined view and nothing else - a presentation would otherwise show
/// its slides twice, once inside the combined view and once per slide view, and
/// a PDF would list one tab per page next to the tab that already has them all.
///
/// Services without a combined view - plain text and images among them - keep
/// whatever views they do offer.
static odr::HtmlViews CoreWrapperSelectViews(const odr::HtmlViews &views,
                                             odr::DocumentType documentType) {
    bool isSpreadsheet = documentType == odr::DocumentType::spreadsheet;
    bool hasCombinedView = std::any_of(views.begin(), views.end(), CoreWrapperIsCombinedView);

    odr::HtmlViews selected;
    for (const odr::HtmlView &view : views) {
        bool isCombinedView = CoreWrapperIsCombinedView(view);
        bool skip = isSpreadsheet ? isCombinedView : (hasCombinedView && !isCombinedView);
        if (skip) {
            continue;
        }

        selected.push_back(view);
    }

    return selected;
}

static struct sockaddr_in CoreWrapperLoopbackAddress(std::uint32_t port) {
    struct sockaddr_in address = {};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<in_port_t>(port));
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    return address;
}

/// Whether the port is free, asked by binding it and letting go again.
///
/// Without this, a port some other app is already listening on would answer the
/// readiness probe below and the app would spend the rest of its life handing
/// the web view addresses on a server that knows nothing about our documents.
///
/// `SO_REUSEADDR` matches what cpp-httplib sets, so a connection of ours still
/// in TIME_WAIT does not read as somebody else's port. `SO_REUSEPORT`, which
/// httplib also sets, is deliberately not: it would let this bind succeed
/// alongside a foreign listener, which is the case being ruled out.
static BOOL CoreWrapperPortIsFree(std::uint32_t port) {
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) {
        return NO;
    }

    int reuse = 1;
    setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in address = CoreWrapperLoopbackAddress(port);
    int bound = bind(handle, reinterpret_cast<struct sockaddr *>(&address), sizeof(address));
    close(handle);

    return bound == 0;
}

static BOOL CoreWrapperPortAnswers(std::uint32_t port) {
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) {
        return NO;
    }

    struct sockaddr_in address = CoreWrapperLoopbackAddress(port);
    int connected = connect(handle, reinterpret_cast<struct sockaddr *>(&address), sizeof(address));
    close(handle);

    return connected == 0;
}

static std::optional<odr::HttpServer> g_server;

/// Set when `listen` comes back, which it only does when the bind failed or the
/// server was stopped. While it is clear, the socket on the port is ours.
static std::atomic<bool> g_serverStopped{false};

/// `listen` binds the socket on the server's own thread, so without waiting the
/// first request can lose the race and get "connection refused" instead of a
/// document.
static BOOL CoreWrapperWaitForServer(std::uint32_t port, NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (true) {
        if (g_serverStopped.load()) {
            return NO;
        }
        // re-checked afterwards: a port that answers between our bind test and
        // this point belongs to whoever won the race, and if that is not us
        // then listen() has come back by now
        if (CoreWrapperPortAnswers(port) && !g_serverStopped.load()) {
            return YES;
        }
        if ([deadline timeIntervalSinceNow] <= 0) {
            return NO;
        }

        usleep(10 * 1000);
    }
}

/// Brings up the one server the app has, on first use, and leaves it running
/// for the rest of the process. Returns NO when the port could not be taken -
/// another app may hold it - in which case translate falls back to files.
///
/// Only attempted once: a port that is taken now is not going to be free on the
/// next document either, and retrying would fork the state of `g_server`.
static BOOL CoreWrapperStartServer() {
    static BOOL running = NO;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        if (!CoreWrapperPortIsFree(kCoreWrapperHttpPort)) {
            return;
        }

        NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"odrcore-server"];

        odr::HttpServer::Config config;
        config.cache_path = std::string([cachePath UTF8String]);

        try {
            std::filesystem::create_directories(config.cache_path);
            g_server = odr::HttpServer(config);
        } catch (...) {
            return;
        }

        // listen() only returns once the server is stopped, and the server is
        // stopped when the process ends, so this thread is never joined
        std::thread([] {
            try {
                g_server->listen("127.0.0.1", kCoreWrapperHttpPort);
            } catch (...) {
            }

            g_serverStopped.store(true);
        }).detach();

        running = CoreWrapperWaitForServer(kCoreWrapperHttpPort, 5);
    });

    return running;
}

static NSString *const kCoreWrapperHttpHost = @"127.0.0.1";

/// Where the server serves a view: `HttpServer` routes `/file/<prefix>/<path>`
/// to the service connected under that prefix, and the pages ask for their
/// images and fonts relative to that, so those are covered by the same route.
static NSURL *CoreWrapperPageURL(const std::string &prefix, const std::string &path) {
    NSString *escapedPath = [[NSString stringWithUTF8String:path.c_str()]
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];

    NSString *url = [NSString stringWithFormat:@"http://%@:%u/file/%s/%@", kCoreWrapperHttpHost,
                                               static_cast<unsigned int>(kCoreWrapperHttpPort),
                                               prefix.c_str(), escapedPath];

    return [NSURL URLWithString:url];
}

/// odrcore's data files ship inside the app bundle. The path never changes at
/// runtime, so it is set once instead of on every translate call.
static void CoreWrapperEnsureDataPath() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        std::string dataPath = std::string([bundlePath UTF8String]) + "/odrcore";
        odr::GlobalParams::set_odr_core_data_path(dataPath);
    });
}

@implementation CoreWrapper {
    std::optional<odr::Document> _document;
    std::optional<odr::Html> _html;
}

- (BOOL)translate:(NSString *)inputPath
            cache:(NSString *)cachePath
             into:(NSString *)outputPath
             with:(NSString *)password
         editable:(BOOL)editable
            error:(NSError **)error {
    @synchronized(self) {
        _pageNames = nil;
        _pageURLs = nil;

        try {
            CoreWrapperEnsureDataPath();

            _html.reset();

            BOOL overHttp = kCoreWrapperServesOverHttp && CoreWrapperStartServer();

            odr::HtmlConfig config;
            config.editable = editable;
            // resource paths are resolved relative to an output directory, and
            // in server mode there is none - odrcore rejects the combination
            config.relative_resource_paths = !overHttp;

            std::string inputPathCpp = std::string([inputPath UTF8String]);

            std::vector<odr::FileType> fileTypes;
            try {
                fileTypes = odr::list_file_types(inputPathCpp);
            } catch (odr::UnsupportedFileType &) {
                fileTypes.clear();
            }
            if (fileTypes.empty()) {
                if (error) {
                    *error = CoreWrapperMakeError(CoreWrapperErrorUnsupportedFileType,
                                                  @"odrcore does not recognise this file type");
                }
                return NO;
            }

            // PDFs are handed to WKWebView instead, which renders them natively
            if (std::find(fileTypes.begin(), fileTypes.end(),
                          odr::FileType::portable_document_format) != fileTypes.end()) {
                if (error) {
                    *error = CoreWrapperMakeError(CoreWrapperErrorUnsupportedFileType,
                                                  @"PDF is rendered by the web view, not by odrcore");
                }
                return NO;
            }

            std::string outputPathCpp = std::string([outputPath UTF8String]);
            std::string cachePathCpp = std::string([cachePath UTF8String]);

            odr::DecodedFile file = odr::open(inputPathCpp);
            if (file.password_encrypted()) {
                std::string passwordCpp = password != nil ? std::string([password UTF8String]) : std::string();
                try {
                    file = file.decrypt(passwordCpp);
                } catch (odr::WrongPasswordError &) {
                    if (error) {
                        *error = CoreWrapperMakeError(CoreWrapperErrorWrongPassword,
                                                      @"wrong password");
                    }
                    return NO;
                }
            }

            if (!file.is_document_file()) {
                if (error) {
                    *error = CoreWrapperMakeError(CoreWrapperErrorUnsupportedFileType,
                                                  @"not a document file");
                }
                return NO;
            }

            odr::DocumentFile documentFile = file.as_document_file();
            odr::DocumentType documentType = documentFile.document_type();
            _document = documentFile.document();

            odr::HtmlService service = odr::html::translate(*_document, cachePathCpp, config);

            // the views are picked before they are rendered: bringing all of them
            // offline first would write out every slide of a presentation only to
            // throw the files away again
            odr::HtmlViews views = CoreWrapperSelectViews(service.list_views(), documentType);
            if (views.empty()) {
                if (error) {
                    *error = CoreWrapperMakeError(CoreWrapperErrorUnknown,
                                                  @"odrcore produced no displayable page");
                }
                return NO;
            }

            NSMutableArray<NSString *> *pageNames = [[NSMutableArray alloc] init];
            NSMutableArray<NSURL *> *pageURLs = [[NSMutableArray alloc] init];

            if (overHttp) {
                // a fresh prefix for every translation, because the web view
                // caches by URL: re-translating after a password or an edit has
                // to end up at an address it has not seen before
                static std::atomic<std::uint64_t> translation{0};
                std::string prefix = "odr" + std::to_string(++translation);

                // drops the service of the document shown before this one, whose
                // pages nobody is going to ask for again, along with its cache.
                // the directory is recreated first because clear() walks it and
                // the system is free to empty the temporary directory for us
                std::filesystem::create_directories(g_server->config().cache_path);
                g_server->clear();
                g_server->connect_service(service, prefix);

                for (const odr::HtmlView &view : views) {
                    [pageNames addObject:[NSString stringWithUTF8String:view.name().c_str()]];
                    [pageURLs addObject:CoreWrapperPageURL(prefix, view.path())];
                }
            } else {
                _html = service.bring_offline(outputPathCpp, views);

                for (const auto &page : _html->pages()) {
                    [pageNames addObject:[NSString stringWithUTF8String:page.name.c_str()]];
                    [pageURLs addObject:[NSURL fileURLWithPath:[NSString stringWithUTF8String:page.path.c_str()]]];
                }
            }

            _pageNames = pageNames;
            _pageURLs = pageURLs;

            return YES;
        } catch (odr::UnknownFileType &) {
            if (error) {
                *error = CoreWrapperMakeError(CoreWrapperErrorUnsupportedFileType,
                                              @"unknown file type");
            }
            return NO;
        } catch (std::exception &e) {
            if (error) {
                *error = CoreWrapperMakeError(CoreWrapperErrorUnknown,
                                              [NSString stringWithUTF8String:e.what()]);
            }
            return NO;
        } catch (...) {
            if (error) {
                *error = CoreWrapperMakeError(CoreWrapperErrorUnknown, @"unknown failure in odrcore");
            }
            return NO;
        }
    }
}

+ (BOOL)isServedURL:(NSURL *)url {
    return [url.scheme isEqualToString:@"http"] && [url.host isEqualToString:kCoreWrapperHttpHost]
        && url.port.unsignedIntValue == kCoreWrapperHttpPort;
}

- (BOOL)backTranslate:(NSString *)diff into:(NSString *)outputPath error:(NSError **)error {
    @synchronized(self) {
        if (!_document.has_value()) {
            if (error) {
                *error = CoreWrapperMakeError(CoreWrapperErrorUnknown,
                                              @"no document has been translated yet");
            }
            return NO;
        }

        try {
            odr::html::edit(*_document, [diff UTF8String]);
            _document->save([outputPath UTF8String]);

            return YES;
        } catch (std::exception &e) {
            if (error) {
                *error = CoreWrapperMakeError(CoreWrapperErrorUnknown,
                                              [NSString stringWithUTF8String:e.what()]);
            }
            return NO;
        } catch (...) {
            if (error) {
                *error = CoreWrapperMakeError(CoreWrapperErrorUnknown, @"unknown failure in odrcore");
            }
            return NO;
        }
    }
}

@end
