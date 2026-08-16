/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for displaying and editing documents.
*/

import StoreKit
import UIKit
import UIKit.UIPrinter
import WebKit

// taken from: https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app
class DocumentViewController: UIViewController, DocumentDelegate, UISearchBarDelegate,
    SKStoreProductViewControllerDelegate, WKNavigationDelegate
{

    private var browserTransition: DocumentBrowserTransitioningDelegate?
    private var hasStartedAds = false
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

    /// The fallback for what odrcore does not render: what WKWebView and the
    /// system decoders can show on their own. Not derived from odrcore's format
    /// table — this is the other side of it.
    private let systemRenderedExtensions = [
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
    /// Where the ad goes. ``AdSlot`` adds the banner as a subview; empty in the paid app.
    @IBOutlet weak var bannerSlot: UIView!
    @IBOutlet weak var bannerSlotHeight: NSLayoutConstraint!
    @IBOutlet weak var barButtonItem: UIBarButtonItem!
    @IBOutlet weak var searchButton: UIBarButtonItem!
    @IBOutlet weak var editButton: UIBarButtonItem!
    /// The gaps behind those two. A button that leaves the bar takes its gap
    /// with it, or what stays drifts off the trailing edge.
    @IBOutlet weak var editButtonSpacer: UIBarButtonItem!
    @IBOutlet weak var searchButtonSpacer: UIBarButtonItem!

    /// The bar as the storyboard has it, taken before anything is removed, since
    /// that is the only moment every button is there to be read.
    private lazy var toolBarItems: [UIBarButtonItem] = toolBar.items ?? []

    /// Whether the document on screen can be edited and searched. Neither button
    /// stays in the bar when it cannot be used.
    private var canEdit = false { didSet { updateToolBar() } }
    /// The same slot the pencil sits in, showing the way out of the edit it
    /// started — as on OpenDocument.droid, where edit mode replaces the bar
    /// rather than emptying it.
    private var isEditingDocument = false { didSet { updateEditButtonRole() } }
    private var canSearch = false {
        didSet {
            updateToolBar()

            if !canSearch {
                hideSearchBar()
            }
        }
    }

    /// What OpenDocument.droid gets from `loadWithOverviewMode`, which iOS has
    /// no setting for: a page wider than the screen is zoomed out until it fits
    /// instead of running off the edge.
    ///
    /// odrcore asks for that by leaving the initial scale out of the viewport
    /// meta - `width=device-width` alone, which every browser but a web view in
    /// overview mode reads as "lay out at screen width and let the rest
    /// overflow". A page that names its scale (a spreadsheet, a csv) means it,
    /// and is left alone.
    ///
    /// Only for what odrcore served, which is why `origin` is checked here as
    /// well as before the script is installed: the same web view shows the
    /// formats odrcore does not handle, and follows links out of a document.
    /// Their viewport is their author's to write, and rewriting it would throw
    /// away what it says - `user-scalable=no`, a maximum scale, a `viewport-fit`.
    private static func fitToWidthScript(servedFrom origin: String) -> String {
        """
        (function () {
            if (location.origin !== '\(origin)') {
                return;
            }

            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta || (meta.content || '').indexOf('initial-scale') !== -1) {
                return;
            }

            var width = document.documentElement.scrollWidth;
            if (width > window.innerWidth) {
                meta.setAttribute('content', 'width=' + width + ',user-scalable=yes');
            }
        })();
        """
    }

    /// Arms ``fitToWidthScript(servedFrom:)`` for a page that came off our own
    /// server, and disarms it for anything else. At document end rather than on
    /// `didFinish`, so the page is fitted before it is first drawn instead of
    /// jumping once the images are in.
    private func installFitToWidth(for url: URL) {
        let scripts = webview.configuration.userContentController
        scripts.removeAllUserScripts()

        guard CoreWrapper.isServedURL(url),
            let scheme = url.scheme, let host = url.host, let port = url.port
        else {
            return
        }

        scripts.addUserScript(
            WKUserScript(
                source: Self.fitToWidthScript(servedFrom: "\(scheme)://\(host):\(port)"),
                injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    /// Fills the banner slot when no ad does. Sits on top of `bannerSlot` rather than in the
    /// layout chain, so the slot keeps its height and nothing below it moves.
    private let houseAdView = HouseAdView()

    private lazy var adSlot: AdSlot = {
        let slot = AdSlot()
        slot.onNoAd = { [weak self] in self?.showHouseAd() }
        slot.onAd = { [weak self] in self?.houseAdView.isHidden = true }

        return slot
    }()

    private var searchBarHeightWhenShown: NSLayoutConstraint?
    private var searchBarHeightWhenHidden: NSLayoutConstraint?
    private lazy var pageTabBarHeight = pageTabBar.heightAnchor.constraint(equalToConstant: 0)

    private var isFullscreen = false

    public var document: Document? {
        didSet {
            document?.delegate = self
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // once, not on every appearance: a second target would parse the
        // document twice for a single tap, and a second set of constraints
        // would fight the first
        pageTabBar.addTarget(self, action: #selector(pageSelected(sender:)), for: .valueChanged)
        webview.navigationDelegate = self

        searchBar.delegate = self
        searchBar.showsCancelButton = true
        searchBarHeightWhenShown = searchBar.heightAnchor.constraint(equalToConstant: 56)
        searchBarHeightWhenHidden = searchBar.heightAnchor.constraint(equalToConstant: 0)

        setVCconstraints()
        hideSearchBar()

        // the chevron says where it goes; the words are for VoiceOver, which is
        // the one reader a glyph is no shorter for
        barButtonItem.accessibilityLabel = NSLocalizedString("back_to_documents", comment: "")
        updateEditButtonRole()

        // nothing is editable or searchable until a page says so
        updateToolBar()

        setUpHouseAd()
    }

    private func setUpHouseAd() {
        houseAdView.isHidden = true
        houseAdView.translatesAutoresizingMaskIntoConstraints = false
        houseAdView.onTap = { [weak self] in
            self?.openProOnAppStore()
        }

        view.addSubview(houseAdView)

        NSLayoutConstraint.activate([
            houseAdView.leadingAnchor.constraint(equalTo: bannerSlot.leadingAnchor),
            houseAdView.trailingAnchor.constraint(equalTo: bannerSlot.trailingAnchor),
            houseAdView.topAnchor.constraint(equalTo: bannerSlot.topAnchor),
            houseAdView.bottomAnchor.constraint(equalTo: bannerSlot.bottomAnchor),
        ])
    }

    /// odrcore renders a page only once this web view asks for it, so a document
    /// that falls over halfway through translating falls over here rather than
    /// in `translate`. Only the main frame counts: a link in the document
    /// answering 404 is not this document failing to render.
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

        // the fallback loads a file or an HTML string, so this cannot recurse
        documentLoadingError(doc, error: DocumentError.pageNotServed)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateSearchButton()
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

        document?.webview = webview

        if !Features.withAds {
            hideBannerSlot()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // the consent form is modal, so it has to wait for the window hierarchy - viewWillAppear
        // is too early. This runs again on every reappearance, hence the flag.
        guard Features.withAds, !hasStartedAds else {
            return
        }
        hasStartedAds = true

        adSlot.start(in: bannerSlot, from: self)
    }

    /// The banner's size follows the orientation; the consent behind it does not.
    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        guard Features.withAds else { return }

        // afterwards, not alongside: the slot only has its new width once the rotation settled
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.adSlot.resize()
        }
    }

    /// From iOS 26 the bar's buttons are glass capsules filling its whole
    /// height, which whatever is pinned to its bottom edge would cut off. Older
    /// bars have a background of their own and want no such gap.
    private static var toolBarBottomMargin: CGFloat {
        if #available(iOS 26.0, *) {
            return 8
        }

        return 0
    }

    func setVCconstraints() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        bannerSlot.translatesAutoresizingMaskIntoConstraints = false
        pageTabBar.translatesAutoresizingMaskIntoConstraints = false
        webview.translatesAutoresizingMaskIntoConstraints = false

        searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        searchBar.topAnchor.constraint(equalTo: toolBar.bottomAnchor, constant: Self.toolBarBottomMargin).isActive =
            true

        bannerSlot.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        bannerSlot.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        bannerSlot.topAnchor.constraint(equalTo: searchBar.bottomAnchor).isActive = true
        // no height here: that is bannerSlotHeight from the storyboard, which
        // hideBannerSlot zeroes, and a second one would fight it

        // below the banner, which is why the tab bar is not in the tool bar's
        // stack: an arranged subview is placed by the stack, and these would be
        // a second answer to the same question
        pageTabBar.topAnchor.constraint(equalTo: bannerSlot.bottomAnchor).isActive = true
        pageTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        pageTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        pageTabBarHeight.isActive = true

        webview.topAnchor.constraint(equalTo: pageTabBar.bottomAnchor).isActive = true
        webview.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webview.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webview.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    /// The paid app has no ad and no house ad either, so the slot collapses.
    private func hideBannerSlot() {
        houseAdView.isHidden = true
        bannerSlotHeight.constant = 0.0
    }

    /// No ad to show, so the slot promotes the paid app instead of collapsing.
    ///
    /// This is our own view - nothing is fetched and no identifier is read - so it is as valid on
    /// the path where the user refused consent as on the one where an ad request merely came back
    /// empty.
    private func showHouseAd() {
        houseAdView.rotate()

        houseAdView.isHidden = false

        AnalyticsManager.shared.report("house_ad_shown")
    }

    private func openProOnAppStore() {
        AnalyticsManager.shared.report("house_ad_tapped")
        // OpenDocument.droid's name for the same intent
        AnalyticsManager.shared.report(AnalyticsConstants.eventAddToCart)

        let store = SKStoreProductViewController()
        store.delegate = self

        // presented over the document rather than sending the user out to the App Store app
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
        isFullscreen.toggle()

        AnalyticsManager.shared.report(isFullscreen ? "menu_fullscreen_enter" : "menu_fullscreen_leave")

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

    /// One button, both ways: the pencil starts an edit and the save glyph ends
    /// it. See ``updateEditButtonRole()``.
    @IBAction func editOrSave(_ sender: UIBarButtonItem) {
        if isEditingDocument {
            // the file holds the edit once it is written, so leaving edit mode
            // reads back what was saved. A save that failed stays in the edit,
            // which is the only place that text still exists.
            saveContent { success in
                guard success else { return }

                self.document?.edit = false
            }
        } else {
            editDocument()
        }
    }

    private func updateToolBar() {
        toolBar.items = toolBarItems.filter { item in
            if item === editButton || item === editButtonSpacer {
                return canEdit
            }
            if item === searchButton || item === searchButtonSpacer {
                return canSearch
            }

            return true
        }
    }

    /// Offered for the documents that can be edited, whether or not one is being
    /// edited right now — the button is the way both into an edit and out of it.
    private func updateEditButton() {
        canEdit = document?.isEditable ?? false
        isEditingDocument = document?.edit ?? false
    }

    /// A pencil to start an edit, and the save glyph to write one. The label goes
    /// with it: VoiceOver reads that, not the glyph.
    private func updateEditButtonRole() {
        editButton.image = UIImage(systemName: isEditingDocument ? "square.and.arrow.down" : "pencil")
        editButton.accessibilityLabel = NSLocalizedString(
            isEditingDocument ? "action_edit_save" : "menu_edit", comment: "")
    }

    /// Asked of the page rather than guessed from the format: odrcore writes the
    /// `odr` object into what it renders as a document or as text, and into
    /// nothing else — a pdf picks the button up on its own once it does.
    private func updateSearchButton() {
        webview.evaluateJavaScript("typeof odr === 'object' && typeof odr.search === 'function'") {
            [weak self] available, _ in
            self?.canSearch = available as? Bool ?? false
        }
    }

    @IBAction func searchButton(_ sender: UIBarButtonItem) {
        AnalyticsManager.shared.report("menu_search")
        AnalyticsManager.shared.report(AnalyticsConstants.eventSearch)

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
        callSearch("odr.searchNext", with: searchText)
    }

    private func findAll(searchText: String) {
        callSearch("odr.search", with: searchText)
    }

    private func callSearch(_ function: String, with searchText: String) {
        // an unescaped quote or backslash in the query would break the call
        // apart rather than search for itself
        let escaped =
            searchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        webview?.evaluateJavaScript("\(function)(\"\(escaped)\")") { _, error in
            if let error {
                CrashManager.shared.log(error)
            }
        }
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

                        // nothing was written, so closing is the discard
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

    /// Also reached through viewDidDisappear, so the document is dropped rather
    /// than closed a second time on the way out.
    func closeCurrentDocument() {
        document?.close()
        document = nil

        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func showMenu(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // neither editing nor saving is in here: both are the one button in the bar

        if document?.edit ?? false {
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("menu_discard_changes", comment: ""), style: .destructive,
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

    /// Reads the document off disk again, which drops the edit, and leaves edit
    /// mode with it — the only way back to reading without saving.
    func discardChanges() {
        AnalyticsManager.shared.report("menu_edit_discard")

        document?.edit = false
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
        let alert = UIAlertController(
            title: nil, message: message,
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)

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
        guard let url = doc.result else {
            self.webview.loadHTMLString(
                "<html><h1>\(NSLocalizedString("loading", comment: ""))</h1></html>", baseURL: nil)

            return
        }

        installFitToWidth(for: url)

        // pages come off the loopback server; a file URL needs read access
        // granted along with it
        if url.isFileURL {
            self.webview.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            self.webview.load(URLRequest(url: url))
        }
    }

    func documentEncrypted(_ doc: Document) {
        // the document is opened before this controller is presented, so the
        // first attempt has nothing to present the prompt on
        if viewIfLoaded?.window == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.documentEncrypted(doc)
            }

            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("toast_error_password_protected", comment: ""), message: "", preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = ""
        }
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("cancel", comment: ""), style: .cancel,
                handler: { [weak self] action in
                    self?.returnToDocuments(action)
                }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("ok", comment: ""), style: .default,
                handler: { [weak self, weak alert] _ in
                    self?.document?.password = alert?.textFields?.first?.text ?? ""
                }))

        self.present(alert, animated: true, completion: nil)
    }

    func documentLoadingError(_ doc: Document, error: Error) {
        progressBar.isHidden = true

        // attention: wrong for extensions like ".pages.zip"
        let fileType = doc.fileURL.pathExtension.lowercased()

        let fileName = doc.fileURL.absoluteString.lowercased()
        if systemRenderedExtensions.contains(where: fileName.hasSuffix) {
            // not odrcore's to render, but the web view knows the format
            self.webview.loadFileURL(doc.fileURL, allowingReadAccessTo: doc.fileURL)

            canEdit = false
            canSearch = false

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

        // neither is known until the page it produces is loaded
        canEdit = false
        canSearch = false
    }

    func documentLoadingCompleted(_ doc: Document) {
        AnalyticsManager.shared.report("load_odf_success")

        progressBar.isHidden = true

        updateEditButton()

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
    /// currently needs.
    private func updatePageTabBarHeight() {
        pageTabBarHeight.constant = pageTabBar.isHidden ? 0 : pageTabBar.preferredHeight
    }
}
