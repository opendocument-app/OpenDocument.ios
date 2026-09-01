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

    /// The width the banner was last asked for at. Nil until consent settles and ``load()``
    /// makes the first request.
    private var requestedWidth: CGFloat?

    /// Whether a banner has ever filled.
    private var hasAd = false

    /// The pending ask for a slot that did not fill.
    private var retry: DispatchWorkItem?

    private var retryDelay = AdSlot.firstRetryDelay

    /// 10s, 20s, 40s, then the 60s the unit refreshes at. Not shorter: the sdk throttles a burst
    /// of failed requests itself.
    private static let firstRetryDelay: TimeInterval = 10
    private static let maxRetryDelay: TimeInterval = 60

    deinit {
        retry?.cancel()
    }

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

    /// Asks for a banner sized to the slot as it is now: an anchored adaptive banner keeps the
    /// shape it was requested at. Never the first request - that one waits for consent.
    func resize() {
        guard requestedWidth != nil else { return }

        load()
    }

    private func load() {
        guard let view = host?.view else { return }

        let width = view.frame.inset(by: view.safeAreaInsets).size.width

        // a transition that left the width alone needs no new ad
        guard width > 0, width != requestedWidth else { return }
        requestedWidth = width

        bannerView.adSize = currentOrientationAnchoredAdaptiveBanner(width: width)

        retry?.cancel()
        retryDelay = AdSlot.firstRetryDelay

        bannerView.load(Request())
    }

    /// Asks again for a hidden banner, which the unit will not refresh. Reschedules itself before
    /// it asks: a request that never comes back must not end the chain. A suspended app cannot
    /// fire the work item, so backgrounding needs no guard.
    private func scheduleRetry() {
        retry?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.retryDelay = min(self.retryDelay * 2, AdSlot.maxRetryDelay)
            self.scheduleRetry()

            self.bannerView.load(Request())
        }

        retry = work

        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
    }

    private func reportNoAd() {
        bannerView.isHidden = true

        onNoAd?()
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        CrashManager.shared.log("ad failed to load: \(error.localizedDescription)")

        // the sdk keeps refreshing an ad that is up; only an empty slot needs asking
        guard !hasAd else { return }

        reportNoAd()
        scheduleRetry()
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        retry?.cancel()
        retryDelay = AdSlot.firstRetryDelay
        hasAd = true

        bannerView.isHidden = false

        onAd?()
    }
}
