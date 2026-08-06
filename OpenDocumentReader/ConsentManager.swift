/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Gathers advertising consent through Google's User Messaging Platform.
*/

import UIKit
import UserMessagingPlatform

/// The consent form in front of the banner in the Lite configuration.
///
/// Google's EU user consent policy requires a certified CMP, integrated with IAB TCF, for traffic
/// from the EEA, the UK and Switzerland. UMP is Google's own, and it is what the Android app has
/// used since it shipped its privacy messaging.
///
/// Which users are asked is decided by UMP, not here: the messages are geo-targeted in AdMob under
/// Privacy & messaging, and the SDK resolves the user's region server-side. Outside a configured
/// region nothing is presented and `canRequestAds` is simply true.
final class ConsentManager {

    static let manager = ConsentManager()

    private init() {}

    /// Brings consent up to date, presenting the form if the user's region requires one, and then
    /// reports whether an ad may be requested.
    ///
    /// Whether we may load an ad is `canRequestAds` and nothing else - never whether the calls
    /// themselves came back clean. The SDK caches the user's decision, so a form that fails to
    /// present, or an update that times out because the device is offline, still leaves an earlier
    /// consent standing, and outside the regions where a form is required at all there is no
    /// decision to fail in the first place. Treating those errors as a refusal would hide the
    /// banner from users who had already said yes.
    ///
    /// It is not a report of what the user chose, either: the property says only that an answer
    /// has been gathered, and "do not consent" is an answer. What that answer allows is
    /// `adsMayUseAdvertisingIdentifier` below.
    ///
    /// The completion runs on the main queue.
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
    /// Runs on every launch from the document browser, because `privacyOptionsRequirementStatus`
    /// and `canRequestAds` answer from a cache that is only filled by an update completing in the
    /// *current* session. Skip it and the privacy entry point disappears on the second launch.
    ///
    /// The completion runs on the main queue.
    func refresh(completion: @escaping () -> Void) {
        requestUpdate { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Whether an ad shown to this user may carry an advertising identifier, and so whether ATT
    /// has anything to govern.
    ///
    /// The CMP writes the TCF signals into `UserDefaults`, as the framework requires. The first
    /// flag of `IABTCF_PurposeConsents` is purpose 1, storing and reading information on the
    /// device; without it Google can serve neither personalised nor non-personalised ads and falls
    /// back to limited ads, which carry no identifier at all. A user who allowed purpose 1 and
    /// refused the personalisation purposes is still shown ads keyed to the identifier for
    /// frequency capping and cross-app reporting, which is what ATT actually gates.
    ///
    /// True where the keys are absent: outside the TCF regions the identifier is used as it
    /// always was.
    var adsMayUseAdvertisingIdentifier: Bool {
        guard let purposeConsents = UserDefaults.standard.string(forKey: "IABTCF_PurposeConsents") else {
            return true
        }

        return purposeConsents.first == "1"
    }

    /// Whether this user has a consent choice worth reopening.
    ///
    /// False outside the regions where a form is configured at all - there is nothing to show, so
    /// the entry point offering it should not be there either.
    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Reopens the consent form so a decision can be changed or withdrawn.
    ///
    /// GDPR Art. 7(3) wants withdrawing consent to be as easy as giving it, and TCF requires the
    /// CMP to be reachable again. Only call this in response to the user asking for it.
    ///
    /// The completion runs on the main queue.
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
                // fires for the mundane offline case too - a device that was asleep
                // times out against fundingchoicesmessages.google.com
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
