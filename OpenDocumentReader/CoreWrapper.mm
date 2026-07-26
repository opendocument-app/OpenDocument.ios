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
#include <odr/odr.hpp>
#include <odr/exceptions.hpp>
#include <odr/global_params.hpp>

#include <algorithm>
#include <optional>
#include <string>

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
        _pagePaths = nil;

        try {
            CoreWrapperEnsureDataPath();

            _html.reset();

            odr::HtmlConfig config;
            config.editable = editable;

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

            _html = service.bring_offline(outputPathCpp, views);

            NSMutableArray<NSString *> *pageNames = [[NSMutableArray alloc] init];
            NSMutableArray<NSString *> *pagePaths = [[NSMutableArray alloc] init];
            for (const auto &page : _html->pages()) {
                [pageNames addObject:[NSString stringWithUTF8String:page.name.c_str()]];
                [pagePaths addObject:[NSString stringWithUTF8String:page.path.c_str()]];
            }

            _pageNames = pageNames;
            _pagePaths = pagePaths;

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
