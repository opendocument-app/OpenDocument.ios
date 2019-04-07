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

@implementation CoreWrapper
- (BOOL)translate:(NSString *)inputPath into:(NSString *)outputPath at:(NSNumber *)page {
    try {
        odr::TranslationConfig config = {};
        config.entryOffset = page.intValue;
        config.entryCount = 50;
        auto translator = odr::TranslationHelper::create();
        translator->open([inputPath cStringUsingEncoding:NSUTF8StringEncoding]);
        translator->translate([outputPath cStringUsingEncoding:NSUTF8StringEncoding], config);
    } catch (...) {
        return false;
    }
    
    return true;
}
@end
