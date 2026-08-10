/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Gathers advertising consent through Google's User Messaging Platform.
*/

import UIKit
import UserMessagingPlatform

/// The consent form in front of the banner in the Lite configuration.
///
/// Google's EU user consent policy requires a TCF-integrated CMP for the EEA, the UK and
/// Switzerland; UMP is Google's own, and what the Android app uses. Who is asked is decided by the
/// geo-targeting of the messages in AdMob, not here.
final class ConsentManager {

    static let manager = ConsentManager()

    private init() {}

    /// Brings consent up to date, presenting the form where the region requires one.
    ///
    /// Reports `canRequestAds`: whether an answer is on file, not what it was - "do not consent"
    /// leaves it true. What the answer allows is `adsMayUseAdvertisingIdentifier`. Errors do not
    /// enter into it; the decision is cached, so a failed form or an offline update still leaves
    /// an earlier consent standing.
    ///
    /// Completes on the main queue.
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

    /// Brings consent up to date without ever presenting a form.
    ///
    /// Needed on every launch: `privacyOptionsRequirementStatus` answers from a cache only an
    /// update in the *current* session fills, so skipping it hides the privacy entry point on the
    /// second launch.
    ///
    /// Completes on the main queue.
    func refresh(completion: @escaping () -> Void) {
        requestUpdate { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Whether an ad shown to this user may carry an advertising identifier, which is what ATT
    /// governs.
    ///
    /// The first flag of the TCF signals UMP writes to `UserDefaults` is purpose 1, device storage.
    /// Without it Google falls back to limited ads, which carry no identifier; refusing only
    /// personalisation leaves one in play, for frequency capping and cross-app reporting. Absent
    /// keys mean no TCF region.
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

    /// Reopens the consent form so a decision can be changed or withdrawn, as GDPR Art. 7(3) and
    /// TCF require. Only in response to the user asking.
    ///
    /// Completes on the main queue.
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
