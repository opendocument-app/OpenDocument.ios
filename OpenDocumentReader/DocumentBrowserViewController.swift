/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 A document browser view controller subclass that implements methods for creating, opening, and importing documents.
 */

import UIKit

class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {

    let pageViewController = "pageViewController"

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self

        allowsDocumentCreation = false
        allowsPickingMultipleItems = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        StoreReviewHelper.checkAndAskForReview()

        let userDefaults = UserDefaults.standard
        let wasIntroWatched = userDefaults.bool(forKey: Constants.key_was_intro_watched)

        guard !wasIntroWatched else { return }

        if let pageVC = storyboard?.instantiateViewController(withIdentifier: pageViewController) as? PageViewController
        {
            present(pageVC, animated: true, completion: nil)
        }
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

        let transitionController = self.transitionController(forDocumentURL: documentURL)
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
