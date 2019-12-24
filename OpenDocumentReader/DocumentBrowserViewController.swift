/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A document browser view controller subclass that implements methods for creating, opening, and importing documents.
 */

import UIKit
import Firebase

class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {
    
    let pageViewController = "pageViewController"
    
    var documentController: DocumentViewController? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        
        StoreReviewHelper.checkAndAskForReview()
        
        allowsDocumentCreation = false
        allowsPickingMultipleItems = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let userDefaults = UserDefaults.standard
        let wasIntroWatched = userDefaults.bool(forKey: Constants.key_was_intro_watched)
        
        guard !wasIntroWatched else { return }
        
        if let pageVC = storyboard?.instantiateViewController(withIdentifier: pageViewController) as? PageViewController {
            present(pageVC, animated: true, completion: nil)
        }
        
    }
    
    func documentBrowser(_ controller: UIDocumentBrowserViewController, didImportDocumentAt sourceURL: URL, toDestinationURL destinationURL: URL) {
        print("==> Imported A Document from %@ to %@.")
        
        presentDocument(at: destinationURL)
    }
    
    func documentBrowser(_ controller: UIDocumentBrowserViewController, failedToImportDocumentAt documentURL: URL, error: Error?) {
        let alert = UIAlertController(
            title: "Unable to Import Document",
            message: "An error occurred while trying to import a document: \(error?.localizedDescription ?? "No Description")",
            preferredStyle: .alert)
        
        let action = UIAlertAction(
            title: "OK",
            style: .cancel,
            handler: nil)
        
        alert.addAction(action)
        
        controller.present(alert, animated: true, completion: nil)
    }
    
    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didPickDocumentURLs documentURLs: [URL]) {
        guard let url = documentURLs.first else {
            Crashlytics.sharedInstance().throwException()

            return
        }
        
        presentDocument(at: url)
    }
    
    func presentDocument(at documentURL: URL) {
        let storyBoard = UIStoryboard(name: "Main", bundle: nil)
        
        if (presentedViewController != nil) {
            presentedViewController?.dismiss(animated: false, completion: nil)
        }
        
        let tempController = storyBoard.instantiateViewController(withIdentifier: "TextDocumentViewController")
        let documentViewController = tempController as! DocumentViewController
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
        Analytics.logEvent(AnalyticsEventViewItem, parameters: [
            AnalyticsParameterItemName: shortenedDocumentUrl
        ])
        
        doc.open { [weak self](success) in
            transitionController.loadingProgress = nil
            
            guard success else {
                Crashlytics.sharedInstance().throwException()

                return
            }
            
            self?.present(documentViewController, animated: true, completion: nil)
        }
    }
}

