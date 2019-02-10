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
- (BOOL)translate:(NSString *)inputPath into:(NSString *)outputPath;
@end

#endif /* CoreWrapper_h */
