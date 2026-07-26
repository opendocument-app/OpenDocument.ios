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

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const CoreWrapperErrorDomain;

typedef NS_ERROR_ENUM(CoreWrapperErrorDomain, CoreWrapperError) {
    /// odrcore threw something we have no specific handling for.
    CoreWrapperErrorUnknown = 1,
    /// The document is encrypted and the supplied password did not open it.
    CoreWrapperErrorWrongPassword = 2,
    /// Not a document odrcore can translate. PDFs land here on purpose.
    CoreWrapperErrorUnsupportedFileType = 3,
};

@interface CoreWrapper : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *pageNames;
@property (nonatomic, copy, readonly) NSArray<NSString *> *pagePaths;

- (BOOL)translate:(NSString *)inputPath
            cache:(NSString *)cachePath
             into:(NSString *)outputPath
             with:(nullable NSString *)password
         editable:(BOOL)editable
            error:(NSError **)error;

- (BOOL)backTranslate:(NSString *)diff
                 into:(NSString *)outputPath
                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* CoreWrapper_h */
