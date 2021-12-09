//
//  CoreWrapper.h
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 09.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

#ifndef CoreWrapper_h
#define CoreWrapper_h

#import <Foundation/Foundation.h>

@interface CoreWrapper : NSObject

@property NSArray *pageNames;
@property NSArray *pagePaths;
@property NSNumber *errorCode;

- (bool)translate:(NSString *)inputPath into:(NSString *)outputPath with:(NSString *)password editable:(bool)editable;
- (bool)backTranslate:(NSString *)diff into:(NSString *)outputPath;
@end

#endif /* CoreWrapper_h */
