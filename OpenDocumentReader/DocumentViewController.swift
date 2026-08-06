/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for displaying and editing documents.
*/

import AdSupport
import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UIKit.UIPrinter
import WebKit

// taken from: https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app
class DocumentViewController: UIViewController, DocumentDelegate, BannerViewDelegate, UISearchBarDelegate,
    WKNavigationDelegate
{

    private var browserTransition: DocumentBrowserTransitioningDelegate?
    private var hasGatheredConsent = false
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

    private var EXTENSION_WHITELIST = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "rtfd.zip", "csv", "txt", "jpg", "jpeg", "png",
        "gif", "svg", "pages", "pages.zip", "numbers", "numbers.zip", "key", "key.zip", "mp3", "mp4", "flv", "mkv",
        "3gp", "aac", "bmp", "css", "htm", "html", "js", "json", "mpeg", "oga", "ogv", "sh", "tif", "tiff", "weba",
        "webm", "webp", "xhtml", "xml",
    ]

    @IBOutlet weak var toolBar: UIToolbar!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var pageTabBar: PageTabBar!

    @IBOutlet weak var webview: WKWebView!
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var menuButton: UIBarButtonItem!
    @IBOutlet weak var bannerView: BannerView!
    @IBOutlet weak var bannerViewHeight: NSLayoutConstraint!
    @IBOutlet weak var barButtonItem: UIBarButtonItem!
    @IBOutlet weak var searchButton: UIBarButtonItem!

    private var searchBarHeightWhenShown: NSLayoutConstraint?
    private var searchBarHeightWhenHidden: NSLayoutConstraint?
    private lazy var pageTabBarHeight = pageTabBar.heightAnchor.constraint(equalToConstant: 0)

    private var isFullscreen = false

    public var document: Document? {
        didSet {
            if let doc = document {
                doc.delegate = self
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // once, not on every appearance: a second target would parse the
        // document twice for a single tap
        pageTabBar.addTarget(self, action: #selector(pageSelected(sender:)), for: .valueChanged)

        webview.navigationDelegate = self
    }

    /// odrcore renders a page when this web view asks for it, so a document
    /// that only falls over halfway through translating falls over here rather
    /// than in `translate`. Route that into the same handling, which shows the
    /// error page or the raw file, instead of letting the server's plain text
    /// "Internal Server Error" through.
    ///
    /// Only for the page itself: a link in the document leading somewhere that
    /// answers 404, or a frame inside it doing so, is not this document failing
    /// to render and must not replace it.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
            let response = navigationResponse.response as? HTTPURLResponse,
            response.statusCode >= 400,
            let url = response.url, CoreWrapper.isServedURL(url),
            let doc = document
        else {
            decisionHandler(.allow)

            return
        }

        decisionHandler(.cancel)

        // the fallback loads a file or an HTML string, neither of which comes
        // back as an HTTP response, so this cannot recurse
        documentLoadingError(doc, error: DocumentError.pageNotServed)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard isViewLoaded,
            traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory
        else {
            return
        }

        updatePageTabBarHeight()
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

        document?.webview = self.webview

        if ConfigurationManager.manager.configuration == .lite {
            bannerView.delegate = self
            bannerView.adUnitID = "ca-app-pub-8161473686436957/8123543897"
            bannerView.rootViewController = self
        } else {
            hideBannerView()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // the consent form is presented modally, so it has to wait until this controller
        // is actually in the window hierarchy - viewWillAppear is too early. Both this and
        // viewWillAppear run again on every reappearance; the ask itself is once per
        // controller, and UMP only presents a form when it still needs an answer.
        guard ConfigurationManager.manager.configuration == .lite, !hasGatheredConsent else {
            return
        }
        hasGatheredConsent = true

        ConsentManager.manager.gatherConsent(from: self) { canRequestAds in
            guard canRequestAds else {
                // Refused, but still worth asking for: the "do not consent" answer emits a TC
                // string carrying the special purposes, from which Google selects limited ads
                // server-side - no cookies, no identifiers, no local storage. Showing nothing
                // here would be stricter than the rules require and costs the fill outright.
                //
                // No ATT on this path. Limited ads use no advertising identifier, so there is
                // nothing for Apple's question to govern and asking it would contradict the
                // answer the user just gave.
                self.loadBannerAd()
                return
            }

            // ATT is Apple's separate question about the IDFA and does not stand in for
            // consent under the EU rules. It is only worth putting in front of someone who
            // is going to be shown an ad at all, so it follows the consent form.
            //
            // Asked even when the user allowed storage but refused personalisation: a
            // non-personalised ad still uses the identifier for frequency capping and
            // aggregated reporting across apps, which is what ATT actually gates.
            ATTrackingManager.requestTrackingAuthorization(completionHandler: { _ in
                DispatchQueue.main.async {
                    self.loadBannerAd()
                }
            })
        }
    }

    func setVCconstraints() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        pageTabBar.translatesAutoresizingMaskIntoConstraints = false
        webview.translatesAutoresizingMaskIntoConstraints = false

        searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        searchBar.topAnchor.constraint(equalTo: toolBar.bottomAnchor).isActive = true

        bannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        bannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        bannerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor).isActive = true
        bannerView.heightAnchor.constraint(equalToConstant: 50).isActive = true

        pageTabBar.topAnchor.constraint(equalTo: bannerView.bottomAnchor).isActive = true
        pageTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        pageTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        pageTabBarHeight.isActive = true

        webview.topAnchor.constraint(equalTo: pageTabBar.bottomAnchor).isActive = true
        webview.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webview.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webview.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    func loadBannerAd() {
        let viewWidth = view.frame.inset(by: view.safeAreaInsets).size.width

        bannerView.adSize = currentOrientationAnchoredAdaptiveBanner(width: viewWidth)
        bannerView.load(Request())
    }

    func hideBannerView() {
        bannerView.isHidden = true
        bannerViewHeight.constant = 0.0
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        hideBannerView()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        closeCurrentDocument()
    }

    @objc func pageSelected(sender: PageTabBar) {
        guard let index = sender.selectedIndex else { return }

        document?.page = index
    }

    func showWebsite() {
        AnalyticsManager.shared.report("menu_help")

        guard let url = URL(string: "https://opendocument.app") else { return }

        UIApplication.shared.open(url)
    }

    func toggleFullscreen() {
        isFullscreen = !isFullscreen

        let event: String
        if isFullscreen {
            event = "menu_fullscreen_enter"
        } else {
            event = "menu_fullscreen_leave"
        }
        AnalyticsManager.shared.report(event)

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
        webview?.evaluateJavaScript(
            "odr.searchNext(\"" + searchText + "\")",
            completionHandler: { (value: Any!, error: Error!) -> Void in
                if error != nil {
                    CrashManager.shared.log(error)
                }
            })
    }

    private func findAll(searchText: String) {
        webview?.evaluateJavaScript(
            "odr.search(\"" + searchText + "\")",
            completionHandler: { (value: Any!, error: Error!) -> Void in
                if error != nil {
                    CrashManager.shared.log(error)
                }
            })
    }

    @IBAction func returnToDocuments(_ sender: Any) {
        guard let doc = document else {
            closeCurrentDocument()

            return
        }

        if doc.edit {
            let alert = UIAlertController(
                title: NSLocalizedString("alert_unsaved_changes", comment: ""),
                message: NSLocalizedString("alert_save_now", comment: ""), preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("no", comment: ""), style: .destructive,
                    handler: { (_) in
                        AnalyticsManager.shared.report("alert_unsaved_changes_no")

                        self.discardChanges()
                        self.closeCurrentDocument()
                    }))
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("yes", comment: ""), style: .default,
                    handler: { (_) in
                        AnalyticsManager.shared.report("alert_unsaved_changes_yes")

                        self.saveContent { (success) -> Void in
                            if success {
                                self.closeCurrentDocument()
                            }
                        }
                    }))

            self.present(alert, animated: true, completion: nil)

            AnalyticsManager.shared.report("show_alert_unsaved_changes")
        } else {
            closeCurrentDocument()
        }
    }

    func closeCurrentDocument() {
        document?.close()
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func showMenu(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if document?.isOdf ?? false && !(document?.edit ?? false) {
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("menu_edit", comment: ""), style: .default,
                    handler: { (_) in
                        self.editDocument()
                    }))
        }

        if document?.edit ?? false {
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("action_edit_save", comment: ""), style: .default,
                    handler: { (_) in
                        self.saveContent(completion: nil)
                    }))

            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("menu_discard_changes", comment: ""), style: .default,
                    handler: { (_) in
                        self.discardChanges()
                    }))
        }

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("menu_fullscreen", comment: ""), style: .default,
                handler: { (_) in
                    self.toggleFullscreen()
                }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("menu_cloud_print", comment: ""), style: .default,
                handler: { (_) in
                    self.printDocument()
                }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("action_edit_help", comment: ""), style: .default,
                handler: { (_) in
                    self.showWebsite()
                }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: nil))

        alert.popoverPresentationController?.sourceView = menuButton.value(forKey: "view") as? UIView
        self.present(alert, animated: true, completion: nil)
    }

    func discardChanges() {
        AnalyticsManager.shared.report("menu_edit_discard")

        document?.edit = true
    }

    func saveContent(completion: ((Bool) -> Void)?) {
        AnalyticsManager.shared.report("menu_edit_save")

        guard let doc = document else {
            completion?(false)

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

    func showToast(
        controller: UIViewController, message: String, seconds: Double, color: UIColor? = .gray,
        completion: (() -> Void)? = nil
    ) {
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
        AnalyticsManager.shared.report("menu_edit")

        document?.edit = true
    }

    func printDocument() {
        AnalyticsManager.shared.report("menu_print")

        let printController = UIPrintInteractionController.shared
        let printInfo: UIPrintInfo = UIPrintInfo(dictionary: nil)

        printInfo.outputType = UIPrintInfo.OutputType.general
        printInfo.jobName = "OpenDocument Reader - Document"

        printController.printInfo = printInfo
        printController.printFormatter = webview.viewPrintFormatter()

        printController.present(animated: true, completionHandler: nil)
    }

    func documentUpdateContent(_ doc: Document) {
        guard let url = document?.result else {
            self.webview.loadHTMLString(
                "<html><h1>\(NSLocalizedString("loading", comment: ""))</h1></html>", baseURL: nil)

            return
        }

        // odrcore serves the pages over loopback; the file variant is what the
        // app falls back to when that server could not be brought up
        if url.isFileURL {
            self.webview.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            self.webview.load(URLRequest(url: url))
        }
    }

    func documentEncrypted(_ doc: Document) {
        //        self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document because it is encrypted. Feel free to contact us via tomtasche@gmail.com for further questions.</html>", baseURL: nil)

        if viewIfLoaded?.window == nil {
            // delay because ViewController might not be visible yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.documentEncrypted(doc)
            }

            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("toast_error_password_protected", comment: ""), message: "", preferredStyle: .alert
        )
        alert.addTextField { (textField) in
            textField.text = ""
        }
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("cancel", comment: ""), style: .cancel,
                handler: { [] (_) in
                    self.returnToDocuments("nil" as Any)
                }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("ok", comment: ""), style: .default,
                handler: { [weak alert] (_) in
                    self.document?.password = alert?.textFields?.first?.text ?? ""
                }))

        self.present(alert, animated: true, completion: nil)
    }

    func documentLoadingError(_ doc: Document, error: Error) {
        // attention: wrong for extensions like ".pages.zip"
        let fileType = doc.fileURL.pathExtension.lowercased()

        let fileName = doc.fileURL.absoluteString.lowercased()
        for type in EXTENSION_WHITELIST {
            if !fileName.hasSuffix(type) {
                continue
            }

            self.webview.loadFileURL(doc.fileURL, allowingReadAccessTo: doc.fileURL)

            progressBar.isHidden = true
            searchButton.isEnabled = false

            AnalyticsManager.shared.report(
                "load_success",
                parameters: [
                    AnalyticsConstants.paramItemName: doc.shortenedDocumentUrl,
                    AnalyticsConstants.paramContentType: fileType,
                ])

            return
        }

        self.webview.loadHTMLString(
            "<html><h1>\(NSLocalizedString("error", comment: ""))</h1>\(NSLocalizedString("toast_error_generic", comment: ""))</html>",
            baseURL: nil)

        AnalyticsManager.shared.report(
            "load_error",
            parameters: [
                "code": (error as NSError).code,
                AnalyticsConstants.paramItemName: doc.shortenedDocumentUrl,
                AnalyticsConstants.paramContentType: fileType,
            ])
    }

    func documentLoadingStarted(_ doc: Document) {
        progressBar.isHidden = false
        progressBar.observedProgress = doc.loadProgress
    }

    func documentLoadingCompleted(_ doc: Document) {
        AnalyticsManager.shared.report("load_odf_success")

        progressBar.isHidden = true

        let fileType = doc.fileURL.pathExtension.lowercased()

        AnalyticsManager.shared.report(
            "load_success",
            parameters: [
                AnalyticsConstants.paramItemName: doc.shortenedDocumentUrl,
                AnalyticsConstants.paramContentType: fileType,
            ])
    }

    func documentPagesChanged(_ doc: Document) {
        let pageNames = doc.pageNames ?? []

        pageTabBar.titles = pageNames
        pageTabBar.selectedIndex = pageNames.isEmpty ? nil : 0

        // a single page needs no tab to switch to
        pageTabBar.isHidden = pageNames.count <= 1
        updatePageTabBarHeight()
    }

    /// The tab bar scales with the text size, so its height is whatever it
    /// currently needs rather than a fixed number.
    private func updatePageTabBarHeight() {
        pageTabBarHeight.constant = pageTabBar.isHidden ? 0 : pageTabBar.preferredHeight
    }
}
