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
#include "DocumentMeta.h"

@implementation CoreWrapper
- (int)translate:(NSString *)inputPath into:(NSString *)outputPath at:(NSNumber *)page {
    odr::TranslationConfig config = {};
    
    try {
        auto translator = odr::TranslationHelper::create();
        translator->open([inputPath cStringUsingEncoding:NSUTF8StringEncoding]);
        translator->decrypt("passwort");
    
        config.entryOffset = page.intValue;
        
        const odr::DocumentMeta& meta = translator->getMeta();
        config.entryCount = meta.entryCount;
        
        if (meta.type == odr::DocumentType::TEXT) {
            config.entryCount = 1;
        }
        
        translator->translate([outputPath cStringUsingEncoding:NSUTF8StringEncoding], config);
    } catch (...) {
        return -1;
    }
    
    return config.entryCount;
}
@end
