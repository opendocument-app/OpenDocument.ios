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
#include <odr/open_document_reader.hpp>
#include <odr/exceptions.hpp>

#include <string>
#include <optional>
#include <string>
#include <optional>

@implementation CoreWrapper {
    std::optional<odr::Html> html;
}

- (bool)translate:(NSString *)inputPath into:(NSString *)outputPath with:(NSString *)password editable:(bool)editable {
    @synchronized(self) {
        try {
            _errorCode = 0;
            _pageNames = nil;
            _pagePaths = nil;
            
            if (html.has_value()) {
                html.reset();
            }
            
            odr::HtmlConfig config;
            config.editable = editable;
            
            if (password == nil) {
                password = @"";
            }
            
            auto inputPathC = [inputPath cStringUsingEncoding:NSUTF8StringEncoding];
            auto inputPathCpp = std::string(inputPathC);
            
            std::vector<odr::FileType> fileTypes;
            try {
                fileTypes = odr::OpenDocumentReader::types(inputPathCpp);
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
            
            auto outputPathC = [outputPath cStringUsingEncoding:NSUTF8StringEncoding];
            auto outputPathCpp = std::string(outputPathC);
            
            html = odr::OpenDocumentReader::html(inputPathCpp, [password]() { return std::string([password UTF8String]); }, outputPathCpp, config);
            
            NSMutableArray *pageNames = [[NSMutableArray alloc] init];
            NSMutableArray *pagePaths = [[NSMutableArray alloc] init];
            for (auto &&page : html->pages()) {
                [pageNames addObject:[NSString stringWithCString:page.name.c_str() encoding:[NSString defaultCStringEncoding]]];
                
                [pagePaths addObject:[NSString stringWithCString:page.path.c_str() encoding:[NSString defaultCStringEncoding]]];
            }
            
            _pageNames = pageNames;
            _pagePaths = pagePaths;
        } catch (odr::UnknownFileType&) {
            _errorCode = @(-5);
            return false;
        } catch (odr::WrongPassword&) {
            _errorCode = @(-2);
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
            
            html->edit([diff cStringUsingEncoding:NSUTF8StringEncoding]);
            
            html->save([outputPath cStringUsingEncoding:NSUTF8StringEncoding]);
        } catch (...) {
            _errorCode = @(-3);
            return false;
        }
        
        return true;
    }
}

@end
