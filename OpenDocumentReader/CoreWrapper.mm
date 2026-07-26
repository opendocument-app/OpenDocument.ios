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

            _html = odr::html::translate(*_document, cachePathCpp, config).bring_offline(outputPathCpp);

            NSMutableArray<NSString *> *pageNames = [[NSMutableArray alloc] init];
            NSMutableArray<NSString *> *pagePaths = [[NSMutableArray alloc] init];
            for (const auto &page : _html->pages()) {
                if ([self shouldSkipPageNamed:page.name ofDocumentType:documentType]) {
                    continue;
                }

                [pageNames addObject:[NSString stringWithUTF8String:page.name.c_str()]];
                [pagePaths addObject:[NSString stringWithUTF8String:page.path.c_str()]];
            }

            if (pagePaths.count == 0) {
                if (error) {
                    *error = CoreWrapperMakeError(CoreWrapperErrorUnknown,
                                                  @"odrcore produced no displayable page");
                }
                return NO;
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

/// Presentations and drawings expose their slides as pages and a combined
/// "document" page we do not want; spreadsheets are the other way round.
- (BOOL)shouldSkipPageNamed:(const std::string &)name ofDocumentType:(odr::DocumentType)documentType {
    bool isCombinedPage = name == "document";

    if (documentType == odr::DocumentType::presentation ||
        documentType == odr::DocumentType::drawing) {
        return isCombinedPage ? NO : YES;
    }
    if (documentType == odr::DocumentType::spreadsheet) {
        return isCombinedPage ? YES : NO;
    }
    return NO;
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
