//
//  CoreWrapper.m
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 09.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreWrapper.h"

#include "odr/Reader.h"
#include "odr/Config.h"
#include "odr/Meta.h"

@implementation CoreWrapper {
    odr::Reader translator;
    bool initialized;
}

- (bool)translate:(NSString *)inputPath into:(NSString *)outputPath at:(NSNumber *)page with:(NSString *)password editable:(bool)editable {
    @synchronized(self) {
        try {
            _errorCode = 0;
                    
            if (!initialized) {
                bool opened = translator.open([inputPath cStringUsingEncoding:NSUTF8StringEncoding]);
                if (!opened) {
                    _errorCode = @(-1);
                    return false;
                }
                
                const auto meta = translator.meta();
                
                bool decrypted = !meta.encrypted;
                if (password != nil) {
                    decrypted = translator.decrypt([password cStringUsingEncoding:NSUTF8StringEncoding]);
                }
                
                if (!decrypted) {
                    _errorCode = @(-2);
                    return false;
                }
                
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
                
                initialized = true;
            }
            
            odr::Config config = {};
            config.editable = editable;
            config.entryOffset = page.intValue;
            config.entryCount = 1;
            config.tableLimitRows = 10000;
            
            bool translated = translator.translate([outputPath cStringUsingEncoding:NSUTF8StringEncoding], config);
            if (!translated) {
                _errorCode = @(-4);
                return false;
            }
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
            
            bool success = translator.edit([diff cStringUsingEncoding:NSUTF8StringEncoding]);
            if (!success) {
                _errorCode = @(-4);
                return false;
            }
            
            success = translator.save([outputPath cStringUsingEncoding:NSUTF8StringEncoding]);
            if (!success) {
                _errorCode = @(-5);
                return false;
            }
        } catch (...) {
            _errorCode = @(-3);
            return false;
        }
        
        return true;
    }
}

@end
