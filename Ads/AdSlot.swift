import AppTrackingTransparency
import GoogleMobileAds
import UIKit

/// The banner in the slot above the document, and the consent form in front of it. The controller
/// owns the slot and the house ad that fills it when nothing else does.
final class AdSlot: NSObject, BannerViewDelegate {

    /// Nothing filled the slot, so the house ad can have it.
    var onNoAd: (() -> Void)?

    /// An ad arrived after all - on a later document, or once the network came back.
    var onAd: (() -> Void)?

    private let bannerView = BannerView()
    private weak var host: UIViewController?

    /// Whether an ad has been asked for, which is what ``resize()`` needs to know: consent
    /// settling is the only thing that starts one.
    private var hasRequestedAd = false

    /// Puts the banner in `slot` and gathers consent. Once per controller: the form is modal, so a
    /// second call on reappearance would bring it back.
    func start(in slot: UIView, from viewController: UIViewController) {
        host = viewController

        attach(to: slot)

        bannerView.delegate = self
        bannerView.adUnitID = "ca-app-pub-8161473686436957/8123543897"
        bannerView.rootViewController = viewController

        ConsentManager.manager.gatherConsent(from: viewController) { [weak self] canRequestAds in
            guard canRequestAds else {
                // no answer on file - the form failed, or a first launch offline. Not refusal:
                // "do not consent" is an answer and leaves this true.
                self?.reportNoAd()
                return
            }

            guard ConsentManager.manager.adsMayUseAdvertisingIdentifier else {
                // limited ads, which Google selects server-side and which carry no identifier -
                // so nothing for ATT to govern
                self?.load()
                return
            }

            // ATT is no substitute for consent under the EU rules, so it follows the form
            ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
                DispatchQueue.main.async {
                    self?.load()
                }
            }
        }
    }

    private func attach(to slot: UIView) {
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        slot.addSubview(bannerView)

        // centred rather than pinned: the banner sizes itself from adSize
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])
    }

    /// Sizes the banner for the slot it has now and asks for one that fits.
    ///
    /// An anchored adaptive banner is sized for the width and orientation it was requested at, so
    /// a rotation leaves the one on screen the wrong shape for its slot. OpenDocument.droid
    /// rebuilds it from onConfigurationChanged for the same reason.
    ///
    /// Only once something has been requested: before that, consent has not settled and the slot
    /// belongs to the house ad, which sizes itself.
    func resize() {
        guard hasRequestedAd else { return }

        load()
    }

    private func load() {
        guard let view = host?.view else { return }

        hasRequestedAd = true

        let viewWidth = view.frame.inset(by: view.safeAreaInsets).size.width

        bannerView.adSize = currentOrientationAnchoredAdaptiveBanner(width: viewWidth)
        bannerView.load(Request())
    }

    private func reportNoAd() {
        bannerView.isHidden = true

        onNoAd?()
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        reportNoAd()
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        bannerView.isHidden = false

        onAd?()
    }
}
