/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 A document browser view controller subclass that implements methods for creating, opening, and importing documents.
 */

import UIKit

class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {

    let pageViewController = "pageViewController"

    var documentController: DocumentViewController? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self

        allowsDocumentCreation = false
        allowsPickingMultipleItems = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        StoreReviewHelper.checkAndAskForReview()

        // ahead of the intro guard below: this has to run on every launch, and most launches
        // return there
        refreshPrivacyButton()

        let userDefaults = UserDefaults.standard
        let wasIntroWatched = userDefaults.bool(forKey: Constants.key_was_intro_watched)

        guard !wasIntroWatched else { return }

        if let pageVC = storyboard?.instantiateViewController(withIdentifier: pageViewController) as? PageViewController
        {
            present(pageVC, animated: true, completion: nil)
        }
    }

    // MARK: - Privacy

    /// Brings consent up to date and then shows or hides the entry point that reopens it.
    ///
    /// The app has no settings screen, so the browser's own chrome carries this. It is the only
    /// route back to either choice: the consent form is shown once, and ATT is one-shot per
    /// install.
    private func refreshPrivacyButton() {
        guard ConfigurationManager.manager.configuration == .lite else { return }

        ConsentManager.manager.refresh {
            let item = UIBarButtonItem(
                title: NSLocalizedString("privacy", value: "Privacy", comment: ""),
                style: .plain,
                target: self,
                action: #selector(self.showPrivacyOptions(_:))
            )

            self.additionalTrailingNavigationBarButtonItems = [item]
        }
    }

    @objc private func showPrivacyOptions(_ sender: UIBarButtonItem) {
        let sheet = UIAlertController(
            title: NSLocalizedString("privacy", value: "Privacy", comment: ""), message: nil,
            preferredStyle: .actionSheet)

        // absent outside the regions UMP has a message configured for, where there is no
        // decision on file and nothing for the form to show
        if ConsentManager.manager.privacyOptionsRequired {
            sheet.addAction(
                UIAlertAction(
                    title: NSLocalizedString("privacy_ad_choices", value: "Ad privacy choices", comment: ""),
                    style: .default
                ) { _ in
                    ConsentManager.manager.presentPrivacyOptions(from: self) {}
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

    private func showGenericError() {
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

        if presentedViewController != nil {
            presentedViewController?.dismiss(animated: false, completion: nil)
        }

        guard
            let documentViewController =
                storyBoard
                .instantiateViewController(withIdentifier: "TextDocumentViewController") as? DocumentViewController
        else {
            CrashManager.shared.log("TextDocumentViewController missing from Main.storyboard")

            return
        }
        documentController = documentViewController

        documentViewController.modalPresentationCapturesStatusBarAppearance = true
        documentViewController.loadViewIfNeeded()

        let doc = Document(fileURL: documentURL)

        let transitionController = self.transitionController(forDocumentURL: documentURL)
        transitionController.targetView = documentViewController.webview
        documentViewController.transitionController = transitionController
        transitionController.loadingProgress = doc.loadProgress

        documentViewController.document = doc

        let shortenedDocumentUrl = documentURL.absoluteString.prefix(49) + ".." + documentURL.absoluteString.suffix(49)
        AnalyticsManager.shared.report(
            AnalyticsConstants.eventViewItem,
            parameters: [
                AnalyticsConstants.paramItemName: shortenedDocumentUrl
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
