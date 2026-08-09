import UIKit

/// The way back to the consent choice, which GDPR Art. 7(3) and the TCF require.
enum AdPrivacy {

    /// Brings consent up to date so ``optionsAvailable`` can answer. Completes on the main queue.
    static func refresh(completion: @escaping () -> Void) {
        ConsentManager.manager.refresh(completion: completion)
    }

    /// False where no message is configured: nothing to show, so no entry point either.
    static var optionsAvailable: Bool {
        ConsentManager.manager.privacyOptionsRequired
    }

    static func presentOptions(from viewController: UIViewController, completion: @escaping () -> Void) {
        ConsentManager.manager.presentPrivacyOptions(from: viewController, completion: completion)
    }
}
