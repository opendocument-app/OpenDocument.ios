//
//  AppDelegate.swift
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 06.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // same split OpenDocument.droid uses: reporting only in the ad
        // supported flavor, nothing at all in the paid one
        let reportingEnabled = ConfigurationManager.manager.configuration == .lite
        AnalyticsManager.shared.setEnabled(reportingEnabled)
        CrashManager.shared.setEnabled(reportingEnabled)

        StoreReviewHelper.incrementAppOpenedCount()

        return true
    }

    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
