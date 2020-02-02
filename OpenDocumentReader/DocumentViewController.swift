/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for displaying and editing documents.
*/

import UIKit
import WebKit
import ScrollableSegmentedControl
import UIKit.UIPrinter
import Firebase

// taken from: https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app
class DocumentViewController: UIViewController, UISearchBarDelegate, DocumentDelegate {
    
    private var browserTransition: DocumentBrowserTransitioningDelegate?
    public var transitionController: UIDocumentBrowserTransitionController? {
        didSet {
            if let controller = transitionController {
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
    
    private var EXTENSION_WHITELIST = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "rtfd.zip", "csv", "txt", "jpg", "jpeg", "png", "gif", "svg", "pages", "pages.zip", "numbers", "numbers.zip", "key", "key.zip", "mp3", "mp4", "flv", "mkv", "3gp", "aac", "bmp", "css", "htm", "html", "js", "json", "mpeg", "oga", "ogv", "sh", "tif", "tiff", "weba", "webm", "webp", "xhtml", "xml"]
    
    @IBOutlet weak var searchBarHeight: NSLayoutConstraint!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var searchBarTop: NSLayoutConstraint!
    @IBOutlet weak var segmentedControl: ScrollableSegmentedControl!
    private var initialSelect = false
    
    @IBOutlet weak var webview: WKWebView!
    @IBOutlet weak var progressBar: UIProgressView!
    
    @IBOutlet weak var menuButton: UIBarButtonItem!
    
    private var isFullscreen = false
    
    public var document: Document? {
        didSet {
            if let doc = document {
                doc.delegate = self
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        searchBar.delegate = self
        searchBar.showsCancelButton = true

        hideSearchBar()
        
        segmentedControl.segmentStyle = .textOnly
        segmentedControl.underlineSelected = true
        segmentedControl.fixedSegmentWidth = true
        segmentedControl.addTarget(self, action: #selector(DocumentViewController.segmentSelected(sender:)), for: .valueChanged)
        
        initialSelect = false
        
        document?.webview = self.webview
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        closeCurrentDocument()
    }
    
    @objc func segmentSelected(sender:ScrollableSegmentedControl) {
        if (initialSelect) {
            initialSelect = false
            
            return
        }
        
        document?.page = sender.selectedSegmentIndex
    }
    
    func showWebsite() {
        Analytics.logEvent("menu_help", parameters: nil)
        
        UIApplication.shared.openURL(URL(string: "https://opendocument.app")!)
    }
    
    func toggleFullscreen() {
        isFullscreen = !isFullscreen
        
        let event: String
        if (isFullscreen) {
            event = "menu_fullscreen_enter"
        } else {
            event = "menu_fullscreen_leave"
        }
        Analytics.logEvent(event, parameters: nil)
        
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override var prefersStatusBarHidden: Bool {
        return isFullscreen
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        hideSearchBar()
    }

    func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) {
        findNext()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        findAllAsync(text: searchText)
    }
    
    @IBAction func searchButton(_ sender: UIBarButtonItem) {
        showSearchBar()
    }
    
    private func showSearchBar() {
        searchBar.isHidden = false
        searchBarHeight.constant = 56.0
        searchBarTop.constant = 0.0
    }
    
    private func hideSearchBar() {
        searchBar.text = ""
        searchBar.isHidden = true
        searchBarHeight.constant = 0.0
        searchBarTop.constant = 40.0
        
        self.view.endEditing(true)
    }
    
    private func findNext() {
        //TODO
    }
    
    private func findAllAsync(text searchText: String) {
        //TODO
    }
    
    @IBAction func returnToDocuments(_ sender: Any) {
        guard let doc = document else {
            Crashlytics.sharedInstance().throwException()

            return
        }
        
        if doc.edit {
            let alert = UIAlertController(title: "You have unsaved changes", message: "Save them now?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "No", style: .destructive, handler: { (_) in
                Analytics.logEvent("alert_unsaved_changes_no", parameters: nil)

                self.discardChanges()
                self.closeCurrentDocument()
            }))
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (_) in
                Analytics.logEvent("alert_unsaved_changes_yes", parameters: nil)

                self.saveContent()
                self.closeCurrentDocument()
            }))
            
            self.present(alert, animated: true, completion: nil)
            
            Analytics.logEvent("show_alert_unsaved_changes", parameters: nil)
        } else {
            closeCurrentDocument()
        }
    }
    
    func closeCurrentDocument() {
        guard let doc = document else {
            Crashlytics.sharedInstance().throwException()

            return
        }
        
        doc.close()
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func showMenu(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if (document?.isOdf ?? false && !(document?.edit ?? false)) {
            alert.addAction(UIAlertAction(title: "Edit (EXPERIMENTAL)", style: .default, handler: { (_) in
                self.editDocument()
            }))
        }

        if document?.edit ?? false {
            alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { (_) in
                self.saveContent()
            }))
            
            alert.addAction(UIAlertAction(title: "Discard changes", style: .default, handler: { (_) in
                self.discardChanges()
            }))
        }
        
        alert.addAction(UIAlertAction(title: "Fullscreen", style: .default, handler: { (_) in
            self.toggleFullscreen()
        }))
        alert.addAction(UIAlertAction(title: "Print", style: .default, handler: { (_) in
            self.printDocument()
        }))
        alert.addAction(UIAlertAction(title: "Help!?", style: .default, handler: { (_) in
            self.showWebsite()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        alert.popoverPresentationController?.sourceView = menuButton.value(forKey: "view") as? UIView
        self.present(alert, animated: true, completion: nil)
    }
    
    func discardChanges() {
        Analytics.logEvent("menu_edit_discard", parameters: nil)

        guard let doc = document else {
            Crashlytics.sharedInstance().throwException()

            return
        }
        
        doc.edit = true
    }
    
    func saveContent() {
        Analytics.logEvent("menu_edit_save", parameters: nil)

        guard let doc = document else {
            Crashlytics.sharedInstance().throwException()

            return
        }
        
        doc.save(to: doc.fileURL, for: .forOverwriting) { success in
            let message: String
            let color: UIColor
            if success {
                message = "Successfully saved"
                color = .green
            } else {
                message = "Error while saving"
                color = .red
            }
            
            self.showToast(controller: self, message: message, seconds: 1.5, color: color)
        }
    }
    
    func showToast(controller: UIViewController, message : String, seconds: Double, color: UIColor? = .gray, completion: (() -> Void)? = nil) {
        let alert: UIAlertController!
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        } else {
            alert = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        }

        alert.view.backgroundColor = color
        alert.view.layer.cornerRadius = 15
        
        controller.present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + seconds) {
            alert.dismiss(animated: true)
            
            completion?()
        }
    }
    
    func editDocument() {
        Analytics.logEvent("menu_edit", parameters: nil)

        document?.edit = true
    }
    
    func printDocument() {
        Analytics.logEvent("menu_print", parameters: nil)

        let printController = UIPrintInteractionController.shared
        let printInfo : UIPrintInfo = UIPrintInfo(dictionary: nil)
        
        printInfo.outputType = UIPrintInfo.OutputType.general
        printInfo.jobName = "OpenDocument Reader - Document"
        
        printController.printInfo = printInfo
        printController.printFormatter = webview.viewPrintFormatter()
        
        printController.present(animated: true, completionHandler: nil)
    }
    
    func documentUpdateContent(_ doc: Document) {
        guard let path = document?.result else {
            self.webview.loadHTMLString("<html><h1>Loading</h1></html>", baseURL: nil)
            
            return
        }

        self.webview.loadFileURL(path, allowingReadAccessTo: path)
    }
    
    func documentEncrypted(_ doc: Document) {
//        self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document because it is encrypted. Feel free to contact us via tomtasche@gmail.com for further questions.</html>", baseURL: nil)
        
        if (viewIfLoaded?.window == nil) {
            // delay because ViewController might not be visible yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self.documentEncrypted(doc)
            })
        }
        
        let alert = UIAlertController(title: "Document encrypted", message: "Please enter the password to decrypt this document", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = ""
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [] (_) in
            self.returnToDocuments("nil" as Any)
        }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] (_) in
            let textField = alert?.textFields![0]
            
            self.document?.password = textField!.text!
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func documentLoadingError(_ doc: Document, errorCode: Int) {
        let fileType = doc.fileURL.pathExtension.lowercased()
        for type in EXTENSION_WHITELIST {
            if (!fileType.starts(with: type)) {
                continue
            }

            self.webview.loadFileURL(doc.fileURL, allowingReadAccessTo: doc.fileURL)
            
            progressBar.isHidden = true
            
            Analytics.logEvent("load_success", parameters: [
                AnalyticsParameterItemName: doc.shortenedDocumentUrl,
                AnalyticsParameterContentType: fileType
            ])
            
            return;
        }
        
        self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document. Please try another one while we are working hard to support as many documents as possible. Feel free to contact us via support@opendocument.app for further questions.</html>", baseURL: nil)
        
        Analytics.logEvent(
            "load_error",
            parameters: [
                "code": errorCode,
                AnalyticsParameterItemName: doc.shortenedDocumentUrl,
                AnalyticsParameterContentType: fileType
            ])
    }
    
    func documentLoadingStarted(_ doc: Document) {
        progressBar.isHidden = false
        progressBar.observedProgress = doc.progress
    }
    
    func documentLoadingCompleted(_ doc: Document) {
        Analytics.logEvent("load_odf_success", parameters: nil)
        
        progressBar.isHidden = true
        
        let fileType = doc.fileURL.pathExtension.lowercased()
        
        Analytics.logEvent(
            "load_success",
            parameters: [
                AnalyticsParameterItemName: doc.shortenedDocumentUrl,
                AnalyticsParameterContentType: fileType
            ])
    }
    
    func documentPagesChanged(_ doc: Document) {
        let pageNames = doc.pageNames
        
        var i = 0
        for pageName in pageNames! {
            segmentedControl.insertSegment(withTitle: pageName, at: i)
            
            i += 1
        }
        
        segmentedControl.isHidden = i <= 1
        
        initialSelect = true
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.layoutSubviews()
    }
}
