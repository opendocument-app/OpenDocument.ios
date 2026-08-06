//
//  Constants.swift
//  OpenDocumentReader
//
//  Created by Artsem Lemiasheuski on 19.12.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import Foundation

enum Constants {
    static let onboardingImages = ["onboard1", "onboard2", "onboard3"]

    static let key_was_intro_watched = "wasIntroWatched"

    /// Which of the house ad's rotations comes next.
    static let key_house_ad_index = "houseAdIndex"

    /// ODR Pro on the App Store. This is the *paid* app: on iOS that is `at.tomtasche.reader`,
    /// while on Android the same bundle id names the free one.
    static let proAppStoreId = 1_452_061_743
}
