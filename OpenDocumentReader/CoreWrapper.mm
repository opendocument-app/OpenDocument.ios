//
//  CoreWrapper.m
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

#include <string>
#include <optional>
#include <string>
#include <optional>

@implementation CoreWrapper {
    std::optional<odr::Document> document;
    std::optional<odr::Html> html;
}

- (bool)translate:(NSString *)inputPath cache:(NSString *)cachePath into:(NSString *)outputPath with:(NSString *)password editable:(bool)editable {
    @synchronized(self) {
        try {
            _errorCode = 0;
            _pageNames = nil;
            _pagePaths = nil;

            NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
            std::string bundlePathCpp = std::string([bundlePath UTF8String]);
            odr::GlobalParams::set_odr_core_data_path(bundlePathCpp + "/odrcore");

            html.reset();

            odr::HtmlConfig config;
            config.editable = editable;

            if (password == nil) {
                password = @"";
            }

            auto inputPathC = [inputPath UTF8String];
            auto inputPathCpp = std::string(inputPathC);

            std::vector<odr::FileType> fileTypes;
            try {
                fileTypes = odr::list_file_types(inputPathCpp);
                if (fileTypes.empty()) {
                    _errorCode = @(-5);
                    return false;
                }
            } catch (odr::UnsupportedFileType &e) {
                _errorCode = @(-5);
                return false;
            }

            if (std::find(fileTypes.begin(), fileTypes.end(), odr::FileType::portable_document_format) != fileTypes.end()) {
                _errorCode = @(-5);
                return false;
            }

            auto outputPathC = [outputPath UTF8String];
            auto outputPathCpp = std::string(outputPathC);

            auto cachePathC = [cachePath UTF8String];
            auto cachePathCpp = std::string(cachePathC);

            odr::DecodedFile file = odr::open(inputPathCpp);
            if (file.password_encrypted()) {
                try {
                    file = file.decrypt(std::string([password UTF8String]));
                } catch (odr::WrongPasswordError &) {
                    _errorCode = @(-2);
                    return false;
                }
            }
            if (!file.is_document_file()) {
                _errorCode = @(-5);
                return false;
            }
            document = file.as_document_file().document();

            html = odr::html::translate(*document, cachePathCpp, config).bring_offline(outputPathCpp);

            NSMutableArray *pageNames = [[NSMutableArray alloc] init];
            NSMutableArray *pagePaths = [[NSMutableArray alloc] init];
            for (const auto &page : html->pages()) {
                if (file.is_document_file() && (
                        (((file.as_document_file().document_type() == odr::DocumentType::presentation) ||
                          (file.as_document_file().document_type() == odr::DocumentType::drawing)) &&
                         (page.name != "document")) ||
                        ((file.as_document_file().document_type() == odr::DocumentType::spreadsheet) &&
                         (page.name == "document")))) {
                    continue;
                }

                [pageNames addObject:[NSString stringWithCString:page.name.c_str() encoding:[NSString defaultCStringEncoding]]];
                [pagePaths addObject:[NSString stringWithCString:page.path.c_str() encoding:[NSString defaultCStringEncoding]]];
            }

            _pageNames = pageNames;
            _pagePaths = pagePaths;
        } catch (odr::UnknownFileType&) {
            _errorCode = @(-5);
            return false;
        } catch (std::runtime_error &e) {
            std::cout << e.what() << std::endl;
            _errorCode = @(-3);
            return false;
        } catch (...) {
            _errorCode = @(-3);
            return false;
        }

        return true;
    }
}

- (bool)backTranslate:(NSString *)diff into:(NSString *)outputPath {
    @synchronized(self) {
        try {
            _errorCode = 0;

            odr::html::edit(*document, [diff UTF8String]);

            document->save([outputPath UTF8String]);
        } catch (...) {
            _errorCode = @(-3);
            return false;
        }
        
        return true;
    }
}

@end
