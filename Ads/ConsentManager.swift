/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Gathers advertising consent through Google's User Messaging Platform.
*/

import UIKit
import UserMessagingPlatform

/// Gathers Lite ad consent through UMP using AdMob region settings.
final class ConsentManager {

    static let manager = ConsentManager()

    private init() {}

    /// Refresh consent and present a form when required.
    /// Reports canRequestAds on main; cached consent survives refresh failures.
    func gatherConsent(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        requestUpdate { updated in
            guard updated else {
                self.finish(completion)
                return
            }

            ConsentForm.loadAndPresentIfRequired(from: viewController) { formError in
                if let formError = formError {
                    CrashManager.shared.log("consent form failed: \(formError.localizedDescription)")
                }

                self.finish(completion)
            }
        }
    }

    /// Refresh the session consent cache without presenting a form. Completes on main.
    func refresh(completion: @escaping () -> Void) {
        requestUpdate { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Read TCF purpose 1 (device storage) before requesting ATT.
    /// A missing TCF key allows the ATT request.
    var adsMayUseAdvertisingIdentifier: Bool {
        guard let purposeConsents = UserDefaults.standard.string(forKey: "IABTCF_PurposeConsents") else {
            return true
        }

        return purposeConsents.first == "1"
    }

    /// Whether this user has a consent choice worth reopening. False where no message is
    /// configured: nothing to show, so no entry point either.
    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Present privacy choices on user request. Completes on main.
    func presentPrivacyOptions(from viewController: UIViewController, completion: @escaping () -> Void) {
        ConsentForm.presentPrivacyOptionsForm(from: viewController) { formError in
            if let formError = formError {
                CrashManager.shared.log("privacy options form failed: \(formError.localizedDescription)")
            }

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Reports whether the update succeeded; a failure is logged, never treated as a refusal.
    private func requestUpdate(_ completion: @escaping (Bool) -> Void) {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { requestError in
            if let requestError = requestError {
                // offline is the mundane case, timing out against fundingchoicesmessages.google.com
                CrashManager.shared.log("consent info update failed: \(requestError.localizedDescription)")

                completion(false)
                return
            }

            completion(true)
        }
    }

    private func finish(_ completion: @escaping (Bool) -> Void) {
        let canRequestAds = ConsentInformation.shared.canRequestAds

        if !canRequestAds {
            CrashManager.shared.log("no consent gathered; not requesting an ad")
        }

        DispatchQueue.main.async {
            completion(canRequestAds)
        }
    }
}
