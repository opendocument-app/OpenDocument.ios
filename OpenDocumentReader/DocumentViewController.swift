/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for displaying and editing documents.
*/

import UIKit
import WebKit
import ScrollableSegmentedControl
import UIKit.UIPrinter
import AdSupport

// taken from: https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app
class DocumentViewController: UIViewController, DocumentDelegate, UISearchBarDelegate {
    
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
    
    @IBOutlet weak var toolBar: UIToolbar!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var segmentedControl: ScrollableSegmentedControl!
    private var initialSelect = false
    
    @IBOutlet weak var webview: WKWebView!
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var menuButton: UIBarButtonItem!
    
    @IBOutlet weak var bannerViewHeight: NSLayoutConstraint!
    @IBOutlet weak var barButtonItem: UIBarButtonItem!
    @IBOutlet weak var searchButton: UIBarButtonItem!
    
    private var searchBarHeightWhenShown: NSLayoutConstraint?
    private var searchBarHeightWhenHidden: NSLayoutConstraint?

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
        
        searchBarHeightWhenShown = searchBar.heightAnchor.constraint(equalToConstant: 56)
        searchBarHeightWhenHidden = searchBar.heightAnchor.constraint(equalToConstant: 0)

        setVCconstraints()
        hideSearchBar()
        
        barButtonItem.title = NSLocalizedString("back_to_documents", comment: "")
        
        segmentedControl.segmentStyle = .textOnly
        segmentedControl.underlineSelected = true
        segmentedControl.fixedSegmentWidth = true
        segmentedControl.addTarget(self, action: #selector(DocumentViewController.segmentSelected(sender:)), for: .valueChanged)
        
        initialSelect = false
        
        document?.webview = self.webview
        
        #if !targetEnvironment(macCatalyst)
        if ConfigurationManager.manager.configuration == .lite {
            bannerView.delegate = self
            bannerView.adUnitID = "ca-app-pub-8161473686436957/8123543897"
            bannerView.rootViewController = self
            
            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
                    DispatchQueue.main.async {
                        self.loadBannerAd()
                    }
                })
            } else {
                loadBannerAd()
            }
        }
        #endif
    }
    
    func setVCconstraints() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        webview.translatesAutoresizingMaskIntoConstraints = false
        
        searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        searchBar.topAnchor.constraint(equalTo: toolBar.bottomAnchor).isActive = true

        segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor).isActive = true
        segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        
        webview.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor).isActive = true
        webview.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webview.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webview.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
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
        
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override var prefersStatusBarHidden: Bool {
        return isFullscreen
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        hideSearchBar()
    }

    func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) {
        if let searchText = searchBar.text {
            findNext(searchText: searchText)
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        findAll(searchText: searchText)
    }

    @IBAction func searchButton(_ sender: UIBarButtonItem) {
        showSearchBar()
    }

    private func showSearchBar() {
        searchBar.becomeFirstResponder()
        searchBar.isHidden = false
        searchBarHeightWhenHidden?.isActive = false
        searchBarHeightWhenShown?.isActive = true
    }

    private func hideSearchBar() {
        searchBar.text = ""
        searchBar.isHidden = true
        searchBarHeightWhenHidden?.isActive = true
        searchBarHeightWhenShown?.isActive = false
        
        self.view.endEditing(true)
    }

    private func findNext(searchText: String) {
        webview?.evaluateJavaScript("odr.searchNext(\"" + searchText + "\")", completionHandler: { (value: Any!, error: Error!) -> Void in
            if error != nil {
                fatalError("search failed")
            }
        })
    }

    private func findAll(searchText: String) {
        webview?.evaluateJavaScript("odr.search(\"" + searchText + "\")", completionHandler: { (value: Any!, error: Error!) -> Void in
            if error != nil {
                fatalError("search failed")
            }
        })
    }
    
    @IBAction func returnToDocuments(_ sender: Any) {
        guard let doc = document else {
            fatalError("document is null")

            return
        }
        
        if doc.edit {
            let alert = UIAlertController(title: NSLocalizedString("alert_unsaved_changes", comment: ""), message: NSLocalizedString("alert_save_now", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("no", comment: ""), style: .destructive, handler: { (_) in

                self.discardChanges()
                self.closeCurrentDocument()
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("yes", comment: ""), style: .default, handler: { (_) in

                self.saveContent() { (success) -> () in
                    if (success) {
                        self.closeCurrentDocument()
                    }
                }
            }))
            
            self.present(alert, animated: true, completion: nil)
            
        } else {
            closeCurrentDocument()
        }
    }
    
    func closeCurrentDocument() {
        guard let doc = document else {
            fatalError("document is null")

            return
        }
        
        doc.close()
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func showMenu(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if (document?.isOdf ?? false && !(document?.edit ?? false)) {
            alert.addAction(UIAlertAction(title: NSLocalizedString("menu_edit", comment: ""), style: .default, handler: { (_) in
                self.editDocument()
            }))
        }

        if document?.edit ?? false {
            alert.addAction(UIAlertAction(title: NSLocalizedString("action_edit_save", comment: ""), style: .default, handler: { (_) in
                self.saveContent(completion: nil)
            }))
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("menu_discard_changes", comment: ""), style: .default, handler: { (_) in
                self.discardChanges()
            }))
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("menu_fullscreen", comment: ""), style: .default, handler: { (_) in
            self.toggleFullscreen()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("menu_cloud_print", comment: ""), style: .default, handler: { (_) in
            self.printDocument()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("action_edit_help", comment: ""), style: .default, handler: { (_) in
            self.showWebsite()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: nil))
        
        alert.popoverPresentationController?.sourceView = menuButton.value(forKey: "view") as? UIView
        self.present(alert, animated: true, completion: nil)
    }
    
    func discardChanges() {

        guard let doc = document else {
            fatalError("document is null")

            return
        }
        
        doc.edit = true
    }
    
    func saveContent(completion: ((Bool) -> ())?) {

        guard let doc = document else {
            fatalError("document is null")

            return
        }
        
        doc.save(to: doc.fileURL, for: .forOverwriting) { success in
            let message: String
            let color: UIColor
            if success {
                message = NSLocalizedString("toast_edit_status_saved", comment: "")
                color = .green
            } else {
                message = NSLocalizedString("toast_error_save_failed", comment: "")
                color = .red
            }
            
            self.showToast(controller: self, message: message, seconds: 1.5, color: color) {
                completion?(success)
            }
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

        document?.edit = true
    }
    
    func printDocument() {

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
            self.webview.loadHTMLString("<html><h1>\(NSLocalizedString("loading", comment: ""))</h1></html>", baseURL: nil)
            
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
        
        let alert = UIAlertController(title: NSLocalizedString("toast_error_password_protected", comment: ""), message: "", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = ""
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: { [] (_) in
            self.returnToDocuments("nil" as Any)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: ""), style: .default, handler: { [weak alert] (_) in
            let textField = alert?.textFields![0]
            
            self.document?.password = textField!.text!
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func documentLoadingError(_ doc: Document, errorCode: Int) {
        // attention: wrong for extensions like ".pages.zip"
        let fileType = doc.fileURL.pathExtension.lowercased()
        
        let fileName = doc.fileURL.absoluteString.lowercased()
        for type in EXTENSION_WHITELIST {
            if (!fileName.hasSuffix(type)) {
                continue
            }

            self.webview.loadFileURL(doc.fileURL, allowingReadAccessTo: doc.fileURL)
            
            progressBar.isHidden = true
            searchButton.isEnabled = false
            
            
            return;
        }
        
        self.webview.loadHTMLString("<html><h1>\(NSLocalizedString("error", comment: ""))</h1>\(NSLocalizedString("toast_error_generic", comment: ""))</html>", baseURL: nil)
        
    }
    
    func documentLoadingStarted(_ doc: Document) {
        progressBar.isHidden = false
        progressBar.observedProgress = doc.progress
    }
    
    func documentLoadingCompleted(_ doc: Document) {
        
        progressBar.isHidden = true
        
        let fileType = doc.fileURL.pathExtension.lowercased()
        
    }
    
    func documentPagesChanged(_ doc: Document) {
        let pageNames = doc.pageNames
        
        var i = 0
        for pageName in pageNames! {
            segmentedControl.insertSegment(withTitle: pageName, at: i)
            
            i += 1
        }
                
        if i <= 1 {
            segmentedControl.heightAnchor.constraint(equalToConstant: 0).isActive = true
            segmentedControl.isHidden = true
        } else {
            segmentedControl.heightAnchor.constraint(equalToConstant: 40).isActive = true
            segmentedControl.isHidden = false
        }
        
        initialSelect = true
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.layoutSubviews()
    }
}
