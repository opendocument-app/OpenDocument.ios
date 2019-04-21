/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A document browser view controller subclass that implements methods for creating, opening, and importing documents.
 */

import UIKit

class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        
        allowsDocumentCreation = false
        allowsPickingMultipleItems = false
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
            print("*** No URL Found! ***")
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
        
        guard let documentViewController = tempController as? DocumentViewController else {
            print("*** Unable to cast \(tempController) into a TextDocumentViewController ***")
            return
        }
        
        documentViewController.loadViewIfNeeded()
        
        let doc = Document(fileURL: documentURL)
        
        let transitionController = self.transitionController(forDocumentURL: documentURL)
        transitionController.targetView = documentViewController.webview
        documentViewController.transitionController = transitionController
        transitionController.loadingProgress = doc.loadProgress
        
        documentViewController.document = doc
        
        doc.open { [weak self](success) in
            transitionController.loadingProgress = nil
            
            guard success else {
                print("*** Unable to open the text file ***")
                return
            }
            
            print("==> Document Opened!")
            self?.present(documentViewController, animated: true, completion: nil)
        }
    }
}

