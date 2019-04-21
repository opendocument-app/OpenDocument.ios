/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A document browser view controller subclass that implements methods for creating, opening, and importing documents.
 */

import UIKit
import os.log

/// - Tag: DocumentBrowserViewController
class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {
    
    /// - Tag: viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        
        allowsDocumentCreation = false
        allowsPickingMultipleItems = false
    }
    
    // MARK: UIDocumentBrowserViewControllerDelegate
    
    // Create a new document.
    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {
        
        os_log("==> Creating A New Document.", log: OSLog.default, type: .debug)
        
        let doc = TextDocument()
        let url = doc.fileURL
        
        // Create a new document in a temporary location.
        doc.save(to: url, for: .forCreating) { (saveSuccess) in
            
            // Make sure the document saved successfully.
            guard saveSuccess else {
                os_log("*** Unable to create a new document. ***", log: OSLog.default, type: .error)
                
                // Cancel document creation.
                importHandler(nil, .none)
                return
            }
            
            // Close the document.
            doc.close(completionHandler: { (closeSuccess) in
                
                // Make sure the document closed successfully.
                guard closeSuccess else {
                    os_log("*** Unable to create a new document. ***", log: OSLog.default, type: .error)
                    
                    // Cancel document creation.
                    importHandler(nil, .none)
                    return
                }
                
                // Pass the document's temporary URL to the import handler.
                importHandler(url, .move)
            })
        }
    }
    
    // Import a document.
    func documentBrowser(_ controller: UIDocumentBrowserViewController, didImportDocumentAt sourceURL: URL, toDestinationURL destinationURL: URL) {
        os_log("==> Imported A Document from %@ to %@.",
               log: OSLog.default,
               type: .debug,
               sourceURL.path,
               destinationURL.path)
        
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
    
    // User selected a document.
    
    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didPickDocumentURLs documentURLs: [URL]) {
        
        assert(controller.allowsPickingMultipleItems == false)
        
        assert(!documentURLs.isEmpty,
               "*** We received an empty array of documents ***")
        
        assert(documentURLs.count <= 1,
               "*** We received more than one document ***")
        
        guard let url = documentURLs.first else {
            fatalError("*** No URL Found! ***")
        }
        
        presentDocument(at: url)
    }
    
    // MARK: Document Presentation
    /// - Tag: presentDocuments
    func presentDocument(at documentURL: URL) {
        
        let storyBoard = UIStoryboard(name: "Main", bundle: nil)
        
        if (presentedViewController != nil) {
            presentedViewController?.dismiss(animated: false, completion: nil)
        }
        
        let tempController = storyBoard.instantiateViewController(withIdentifier: "TextDocumentViewController")
        
        guard let documentViewController = tempController as? TextDocumentViewController else {
            fatalError("*** Unable to cast \(tempController) into a TextDocumentViewController ***")
        }
        
        // Load the document view.
        documentViewController.loadViewIfNeeded()
        
        let doc = TextDocument(fileURL: documentURL)
        
        // Get the transition controller.
        let transitionController = self.transitionController(forDocumentURL: documentURL)
        
        // Set up the transition animation.
        transitionController.targetView = documentViewController.webview
        documentViewController.transitionController = transitionController
        
        // Set up the loading animation.
        transitionController.loadingProgress = doc.loadProgress
        
        // Set and open the document.
        documentViewController.document = doc
        
        doc.open { [weak self](success) in
            
            // Remove the loading animation.
            transitionController.loadingProgress = nil
            
            guard success else {
                fatalError("*** Unable to open the text file ***")
            }
            
            os_log("==> Document Opened!", log: OSLog.default, type: .debug)
            self?.present(documentViewController, animated: true, completion: nil)
        }
    }
}

