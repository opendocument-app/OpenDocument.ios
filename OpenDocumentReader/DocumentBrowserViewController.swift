/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 A document browser view controller subclass that implements methods for creating, opening, and importing documents.
 */

import StoreKit
import UIKit

class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate,
    SKStoreProductViewControllerDelegate
{

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self

        allowsDocumentCreation = false
        allowsPickingMultipleItems = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(passUnlocked(_:)), name: Pass.didUnlock, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // before anything that depends on how often the app has been opened:
        // a screenshot run wants one screen and nothing over it
        if let screen = ScreenshotMode.screen {
            showForScreenshot(screen)

            return
        }

        StoreReviewHelper.checkAndAskForReview()

        updateBarButtons()
        refreshPrivacyButton()
    }

    /// Stage each screenshot once, even if the browser reappears.
    private var isShowingScreenshot = false

    private func showForScreenshot(_ screen: ScreenshotMode.Screen) {
        guard !isShowingScreenshot else { return }
        isShowingScreenshot = true

        // Reveal the samples to populate Recents before capturing the browser.
        guard screen != .browser else {
            reveal(ScreenshotMode.browserDocuments) { [weak self] in
                guard let self else { return }

                ScreenshotMode.markReady(self.view)
            }

            return
        }

        // nothing on a missing sample, so the test fails waiting for a document
        // rather than photographing the browser
        guard let document = ScreenshotMode.document(for: screen) else { return }

        presentDocument(at: document)
    }

    /// Reveals each document in turn, one after the previous has landed, and
    /// then says so. One call per document because revealing takes one URL.
    private func reveal(_ documents: [URL], then finish: @escaping () -> Void) {
        guard let next = documents.first else {
            finish()

            return
        }

        revealDocument(at: next, importIfNeeded: false) { [weak self] _, _ in
            self?.reveal(Array(documents.dropFirst()), then: finish)
        }
    }

    // MARK: - Support

    /// Shown once consent has been refreshed. It stays after the pass: withdrawal outlives the ads.
    private var showsPrivacyButton = false

    /// "Support the app" in Lite until the pass is active, where it is seen without a menu, and
    /// the privacy options.
    private func updateBarButtons() {
        var items: [UIBarButtonItem] = []

        if Pass.shared.offersSupport {
            // a glyph: with a title, iOS 26 folds it into the overflow menu, where it is not seen
            let support = UIBarButtonItem(
                image: UIImage(systemName: "heart"), style: .plain, target: self,
                action: #selector(showSupport(_:)))
            support.accessibilityLabel = NSLocalizedString("menu_support", comment: "")
            items.append(support)
        }

        if showsPrivacyButton {
            items.append(
                UIBarButtonItem(
                    title: NSLocalizedString("privacy", value: "Privacy", comment: ""), style: .plain, target: self,
                    action: #selector(showPrivacyOptions(_:))))
        }

        additionalTrailingNavigationBarButtonItems = items
    }

    @objc private func showSupport(_ sender: UIBarButtonItem) {
        AnalyticsManager.shared.report("landing_support")

        PassViewController.present(from: self, feature: nil) { [weak self] in
            self?.openProOnAppStore()
        }
    }

    /// The Pro app's page, over the browser.
    private func openProOnAppStore() {
        AnalyticsManager.shared.report(AnalyticsConstants.eventAddToCart)

        let store = SKStoreProductViewController()
        store.delegate = self
        store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: Constants.proAppStoreId]) {
            loaded, error in
            if let error {
                CrashManager.shared.log(error)
            }

            guard loaded else { return }

            DispatchQueue.main.async {
                self.present(store, animated: true)
            }
        }
    }

    func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        viewController.dismiss(animated: true)
    }

    /// The button goes. The reader says thank you if one is open; otherwise the browser does.
    @objc private func passUnlocked(_ notification: Notification) {
        updateBarButtons()

        guard presentedViewController == nil || presentedViewController is PassViewController else { return }

        let purchased = notification.userInfo?["purchased"] as? Bool ?? false
        AnalyticsManager.shared.report(purchased ? "pass_unlocked" : "pass_restored")

        // the sheet goes away first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.presentedViewController == nil else { return }

            let alert = UIAlertController(
                title: nil, message: NSLocalizedString(purchased ? "pass_unlocked" : "pass_restored", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: ""), style: .default))

            self.present(alert, animated: true)
        }
    }

    // MARK: - Privacy

    /// Refresh consent and expose privacy options in the browser toolbar.
    private func refreshPrivacyButton() {
        guard Features.withAds else { return }

        AdPrivacy.refresh {
            self.showsPrivacyButton = true
            self.updateBarButtons()
        }
    }

    @objc private func showPrivacyOptions(_ sender: UIBarButtonItem) {
        let sheet = UIAlertController(
            title: NSLocalizedString("privacy", value: "Privacy", comment: ""), message: nil,
            preferredStyle: .actionSheet)

        // absent where UMP has no message configured, and so nothing to show
        if AdPrivacy.optionsAvailable {
            sheet.addAction(
                UIAlertAction(
                    title: NSLocalizedString("privacy_ad_choices", value: "Ad privacy choices", comment: ""),
                    style: .default
                ) { _ in
                    AdPrivacy.presentOptions(from: self) {}
                })
        }

        sheet.addAction(
            UIAlertAction(
                title: NSLocalizedString("privacy_tracking", value: "Tracking permission", comment: ""), style: .default
            ) { _ in
                self.showTrackingPermissionHint()
            })

        sheet.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel))

        // an action sheet without this crashes on iPad, where it is a popover
        sheet.popoverPresentationController?.barButtonItem = sender

        present(sheet, animated: true)
    }

    /// ATT cannot be asked twice, so the only way back is the Settings app.
    private func showTrackingPermissionHint() {
        let alert = UIAlertController(
            title: NSLocalizedString("privacy_tracking", value: "Tracking permission", comment: ""),
            message: NSLocalizedString(
                "privacy_tracking_message",
                value:
                    "iOS asks for tracking permission once. You can change it any time in Settings, under Privacy & Security → Tracking. Changing it there closes the app.",
                comment: ""),
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("privacy_open_settings", value: "Open Settings", comment: ""), style: .default
            ) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }

                UIApplication.shared.open(url)
            })

        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel))

        present(alert, animated: true)
    }

    func documentBrowser(
        _ controller: UIDocumentBrowserViewController, didImportDocumentAt sourceURL: URL,
        toDestinationURL destinationURL: URL
    ) {
        presentDocument(at: destinationURL)
    }

    func documentBrowser(
        _ controller: UIDocumentBrowserViewController, failedToImportDocumentAt documentURL: URL, error: Error?
    ) {
        if let error {
            CrashManager.shared.log(error)
        }

        showGenericError()
    }

    func showGenericError() {
        let alert = UIAlertController(
            title: "",
            message: NSLocalizedString("toast_error_generic", comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("ok", comment: ""),
                style: .cancel,
                handler: nil))

        present(alert, animated: true, completion: nil)
    }

    func documentBrowser(
        _ controller: UIDocumentBrowserViewController,
        didPickDocumentURLs documentURLs: [URL]
    ) {
        guard let url = documentURLs.first else { return }

        presentDocument(at: url)
    }

    func presentDocument(at documentURL: URL) {
        CrashManager.shared.setCustomValue(documentURL.absoluteString, forKey: "documentUrl")

        let storyBoard = UIStoryboard(name: "Main", bundle: nil)

        presentedViewController?.dismiss(animated: false, completion: nil)

        guard
            let documentViewController =
                storyBoard
                .instantiateViewController(withIdentifier: "TextDocumentViewController") as? DocumentViewController
        else {
            CrashManager.shared.log("TextDocumentViewController missing from Main.storyboard")

            return
        }

        documentViewController.modalPresentationCapturesStatusBarAppearance = true
        documentViewController.loadViewIfNeeded()

        let doc = Document(fileURL: documentURL)

        let transitionController = self.transitionController(forDocumentAt: documentURL)
        transitionController.targetView = documentViewController.webview
        documentViewController.transitionController = transitionController
        transitionController.loadingProgress = doc.loadProgress

        documentViewController.document = doc

        AnalyticsManager.shared.report(
            AnalyticsConstants.eventViewItem,
            parameters: [
                AnalyticsConstants.paramItemName: doc.shortenedDocumentUrl
            ])

        doc.open { [weak self] success in
            transitionController.loadingProgress = nil

            guard let self else { return }
            guard success else {
                CrashManager.shared.log("opening \(doc.shortenedDocumentUrl) failed")
                self.showGenericError()

                return
            }

            self.present(documentViewController, animated: true, completion: nil)
        }
    }
}
