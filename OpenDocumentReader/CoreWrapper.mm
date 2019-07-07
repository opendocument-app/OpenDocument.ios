//
//  CoreWrapper.m
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 09.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreWrapper.h"

#include "TranslationHelper.h"
#include "TranslationConfig.h"
#include "FileMeta.h"

@implementation CoreWrapper
- (bool)translate:(NSString *)inputPath into:(NSString *)outputPath at:(NSNumber *)page with:(NSString *)password {
    try {
        auto translator = odr::TranslationHelper();
        bool opened = translator.open([inputPath cStringUsingEncoding:NSUTF8StringEncoding]);
        if (!opened) {
            _errorCode = @(-1);
            return false;
        }
        
        const odr::FileMeta& meta = translator.getMeta();
        
        bool decrypted = !meta.encrypted;
        if (password != nil) {
            decrypted = translator.decrypt([password cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        if (!decrypted) {
            _errorCode = @(-2);
            return false;
        }
        
        odr::TranslationConfig config = {};
        config.entryOffset = page.intValue;
        config.entryCount = 1;
        
        NSMutableArray *pageNames = [[NSMutableArray alloc] init];
        if (meta.type == odr::FileType::OPENDOCUMENT_TEXT) {
            [pageNames addObject:@"Text document"];
        } else {
            for (auto page = meta.entries.begin(); page != meta.entries.end(); page++) {
                auto pageName = page->name;
                
                [pageNames addObject:[NSString stringWithCString:pageName.c_str() encoding:[NSString defaultCStringEncoding]]];
            }
        }
        _pageNames = pageNames;
        
        translator.translate([outputPath cStringUsingEncoding:NSUTF8StringEncoding], config);
    } catch (...) {
        _errorCode = @(-3);
        return false;
    }
    
    return true;
}
@end
