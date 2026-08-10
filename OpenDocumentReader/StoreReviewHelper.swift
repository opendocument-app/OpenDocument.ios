//
//  StoreReviewHelper.swift
//  Template1
//
//  Created by Apple on 14/11/17.
//  Copyright © 2017 Mobiotics. All rights reserved.
//
import Foundation
import StoreKit

// taken from: https://medium.com/@abhimuralidharan/asking-customers-for-ratings-and-reviews-from-inside-the-app-in-ios-d85f256dd4ef
struct StoreReviewHelper {

    struct UserDefaultsKeys {
        static let APP_OPENED_COUNT = "APP_OPENED_COUNT"
        /// The open count the prompt was last raised at, so one launch only asks once.
        static let LAST_REVIEW_ASKED_AT = "LAST_REVIEW_ASKED_AT"
    }

    static let Defaults = UserDefaults.standard

    static func incrementAppOpenedCount() {
        let key = UserDefaultsKeys.APP_OPENED_COUNT

        Defaults.set(Defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func checkAndAskForReview() {
        let appOpenCount = Defaults.integer(forKey: UserDefaultsKeys.APP_OPENED_COUNT)

        // asking is not the same as showing: StoreKit rate-limits the prompt
        guard appOpenCount == 3 || (appOpenCount > 0 && appOpenCount % 10 == 0) else { return }

        // the count only moves on launch, but the browser asks from viewDidAppear - so
        // coming back from every document reopened the same eligible launch, asking again
        // and reporting again
        guard Defaults.integer(forKey: UserDefaultsKeys.LAST_REVIEW_ASKED_AT) != appOpenCount else {
            return
        }
        Defaults.set(appOpenCount, forKey: UserDefaultsKeys.LAST_REVIEW_ASKED_AT)

        // the names OpenDocument.droid uses for the same two moments, so the funnel reads
        // the same on both platforms
        AnalyticsManager.shared.report("in_app_review_eligible")

        requestReview()
    }

    private static func requestReview() {
        AnalyticsManager.shared.report("in_app_review_start")

        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive })
            as? UIWindowScene
        {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
