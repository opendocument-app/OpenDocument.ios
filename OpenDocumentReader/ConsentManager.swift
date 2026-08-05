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
    /// The completion runs on the main queue.
    func gatherConsent(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { requestError in
            if let requestError = requestError {
                // fires for the mundane offline case too - a device that was asleep
                // times out against fundingchoicesmessages.google.com
                print("consent info update failed: \(requestError.localizedDescription)")

                self.finish(completion)
                return
            }

            ConsentForm.loadAndPresentIfRequired(from: viewController) { formError in
                if let formError = formError {
                    print("consent form failed: \(formError.localizedDescription)")
                }

                self.finish(completion)
            }
        }
    }

    private func finish(_ completion: @escaping (Bool) -> Void) {
        let canRequestAds = ConsentInformation.shared.canRequestAds

        if !canRequestAds {
            print("consent does not allow requesting ads")
        }

        DispatchQueue.main.async {
            completion(canRequestAds)
        }
    }
}
