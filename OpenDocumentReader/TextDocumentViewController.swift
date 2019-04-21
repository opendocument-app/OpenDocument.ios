/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for displaying and editing documents.
*/

import UIKit
import os.log
import WebKit
import ScrollableSegmentedControl

// taken from: https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app

/// - Tag: textDocumentViewController
class TextDocumentViewController: UIViewController, TextDocumentDelegate {
    
    private var browserTransition: DocumentBrowserTransitioningDelegate?
    public var transitionController: UIDocumentBrowserTransitionController? {
        didSet {
            if let controller = transitionController {
                // Set the transition animation.
                modalPresentationStyle = .custom
                browserTransition = DocumentBrowserTransitioningDelegate(withTransitionController: controller)
                transitioningDelegate = browserTransition
                
            } else {
                modalPresentationStyle = .none
                browserTransition = nil
                transitioningDelegate = nil
            }
        }
    }
    
    @IBOutlet weak var segmentedControl: ScrollableSegmentedControl!
    private var initialSelect = false
    
    @IBOutlet weak var webview: WKWebView!
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var toolbarHeightConstraint: NSLayoutConstraint!
    
    public var document: TextDocument? {
        didSet {
            if let doc = document {
                doc.delegate = self
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        segmentedControl.segmentStyle = .textOnly
        segmentedControl.underlineSelected = true
        segmentedControl.addTarget(self, action: #selector(DocumentViewController.segmentSelected(sender:)), for: .valueChanged)
        
        initialSelect = false
        
        guard let path = document?.result else {
            print("*** No Document Found! ***")
            
            return
        }
        
        self.webview.loadFileURL(path, allowingReadAccessTo: path)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        guard let doc = document else {
            fatalError("*** No Document Found! ***")
        }
        
        doc.close { (success) in
            guard success else {
                fatalError( "*** Error saving document ***")
            }
            
            os_log("==> file Saved!", log: OSLog.default, type: .debug)
        }
    }
    
    @objc func segmentSelected(sender:ScrollableSegmentedControl) {
        if (initialSelect) {
            initialSelect = false
            
            return
        }
        
        document?.setPage(page: sender.selectedSegmentIndex)
    }
    
    @IBAction func returnToDocuments(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - UITextDocumentDelegate Methods
    
    func textDocumentUpdateContent(_ doc: TextDocument) {
        guard let path = document?.result else {
            self.webview.loadHTMLString("<html><h1>Loading</h1></html>", baseURL: nil)
            
            return
        }

        self.webview.loadFileURL(path, allowingReadAccessTo: path)
    }
    
    func textDocumentEncrypted(_ doc: TextDocument) {
//        self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document because it is encrypted. Feel free to contact us via tomtasche@gmail.com for further questions.</html>", baseURL: nil)
        
        let alert = UIAlertController(title: "Document encrypted", message: "Please enter the password to decrypt this document", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = ""
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] (_) in
            let textField = alert?.textFields![0]
            
            self.document?.setPassword(password: textField!.text!)
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func textDocumentLoadingError(_ doc: TextDocument) {
        self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document. Please try another one while we are working hard to support as many documents as possible. Feel free to contact us via tomtasche@gmail.com for further questions.</html>", baseURL: nil)
    }
    
    func textDocumentLoadingStarted(_ doc: TextDocument) {
        progressBar.isHidden = false
        progressBar.observedProgress = doc.progress
    }
    
    func textDocumentLoadingCompleted(_ doc: TextDocument) {
        progressBar.isHidden = true
    }
    
    func textDocumentPageCountChanged(_ doc: TextDocument) {
        let pageCount = doc.pageCount
        
        for i in 1...pageCount {
            segmentedControl.insertSegment(withTitle: String(i), at: i - 1)
        }
        
        segmentedControl.isHidden = pageCount <= 1
        
        initialSelect = true
        segmentedControl.selectedSegmentIndex = 0
    }
}
