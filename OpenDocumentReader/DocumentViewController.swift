/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for displaying and editing documents.
*/

import StoreKit
import UIKit
import UIKit.UIPrinter
import UniformTypeIdentifiers
import WebKit

// taken from: https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app
class DocumentViewController: UIViewController, DocumentDelegate, UISearchBarDelegate,
    SKStoreProductViewControllerDelegate, WKNavigationDelegate, WKUIDelegate
{

    private var browserTransition: DocumentBrowserTransitioningDelegate?
    private var hasStartedAds = false
    /// The navigation that is putting a document on screen, as opposed to the
    /// "loading" or the error page. Nothing but a screenshot asks.
    private var documentNavigation: WKNavigation?
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

            var served = meta.content;
            var natural = document.documentElement.scrollWidth;

            // The web view's own width, which the viewport named below does not
            // change: the visual viewport is that many CSS pixels at that scale.
            function available() {
                var seen = window.visualViewport;

                return seen ? Math.round(seen.width * seen.scale) : window.innerWidth;
            }

            function fit() {
                meta.setAttribute(
                    'content',
                    natural > available() ? 'width=' + natural + ',user-scalable=yes' : served);
            }

            // Across a resize the browser keeps the reader's place by holding on
            // to whatever was against the top of the screen, and here it gets it
            // wrong: the scale changes with the width, and the page comes back
            // hundreds of pixels down - a page or more of a long document on an
            // iPad, which is where the width really does change. It settles
            // there some frames after the resize, so the place the reader was
            // actually at is re-asserted until it has finished, and dropped the
            // moment they take hold of the page themselves.
            var holding = [];

            function hold(place) {
                holding.forEach(clearTimeout);
                holding = [0, 16, 50, 150, 300, 500].map(function (ms) {
                    return setTimeout(function () { window.scrollTo(window.scrollX, place); }, ms);
                });
            }

            window.addEventListener('touchstart', function () {
                holding.forEach(clearTimeout);
                holding = [];
            }, { passive: true });

            // On every resize, not just now: this first runs before the web view
            // has the width it will keep, and a page held at a width it no
            // longer needs is left scrolled off its own top.
            fit();
            window.addEventListener('resize', function () {
                var was = window.scrollY;
                fit();
                hold(was);
            });
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
        webview.uiDelegate = self
        // the way back out of a file opened from a zip's listing. There is
        // nothing to go back to until something has been opened, so it changes
        // nothing for a document that is only read.
        webview.allowsBackForwardNavigationGestures = true

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

    /// odrcore writes every link with `target="_blank"`, so opening a file from
    /// a zip's listing asks for a window this app has none of. It is shown in
    /// the web view that asked instead, and the swipe back leads to the listing.
    ///
    /// Only what odrcore serves: a link out of a document leads to the web, and
    /// this reader is not a browser.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url, CoreWrapper.isServedURL(url) else {
            return nil
        }

        webView.load(navigationAction.request)

        return nil
    }

    /// odrcore renders a page only once this web view asks for it, so a document
    /// that falls over halfway through translating falls over here rather than
    /// in `translate`. Only the main frame counts: a link in the document
    /// answering 404 is not this document failing to render.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame, let doc = document else {
            decisionHandler(.allow)

            return
        }

        // The web view's own answer about what it can draw, asked instead of
        // guessed from the file's name.
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.cancel)

            // the system could not draw the document after all, so odrcore's
            // listing of what is inside it is the better of the two
            if let listing = listingInReserve {
                listingInReserve = nil

                installFitToWidth(for: listing)
                documentNavigation = webview.load(URLRequest(url: listing))

                return
            }

            giveUp(on: doc, with: .unsupported, code: 0)

            return
        }

        listingInReserve = nil

        guard let response = navigationResponse.response as? HTTPURLResponse,
            response.statusCode >= 400,
            let url = response.url, CoreWrapper.isServedURL(url)
        else {
            decisionHandler(.allow)

            return
        }

        decisionHandler(.cancel)

        giveUp(on: doc, with: .broken, code: response.statusCode)
    }

    /// The page never arrived — the socket went away, or the web view could make
    /// nothing of what it was given. Same end as a document that would not
    /// translate.
    ///
    /// Only what odrcore serves: a link out of a document that fails is the
    /// web's problem, not this document's.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        pageFailed(error)
    }

    private func pageFailed(_ error: Error) {
        guard let doc = document, let url = webview.url, CoreWrapper.isServedURL(url) else { return }
        guard !isOurOwnDoing(error) else { return }

        CrashManager.shared.log(error)

        giveUp(on: doc, with: .broken, code: (error as NSError).code)
    }

    /// Whether the reader stopped this load itself. Turning a page cancels the
    /// one before it, and answering a response with `.cancel` — which is how the
    /// listing takes over from a document the system could not draw — is
    /// reported here as a failure too.
    private func isOurOwnDoing(_ error: Error) -> Bool {
        let error = error as NSError

        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return true }

        // WebKitErrorFrameLoadInterruptedByPolicyChange, which has no constant
        return error.domain == "WebKitErrorDomain" && error.code == 102
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateSearchButton()

        // the document is drawn, which is what a screenshot of it waits for -
        // and only the document: the "loading" page finishes first, and a
        // picture of it is a picture of the word "loading"
        if let documentNavigation, navigation === documentNavigation {
            stageScreenshot()
        }
    }

    /// Puts the document into the state its screenshot is of, and only then
    /// says it is ready. A picture of a search is a picture of its hits.
    private func stageScreenshot() {
        switch ScreenshotMode.screen {
        // The search is shown on the ODF document rather than on the pdf: as of
        // odrcore 6.7.0 a hit in a pdf is drawn beside the word it found, not on
        // it. Move this back to `.pdf` once a core lands that places it right.
        case .text:
            let query = ScreenshotMode.query
            showSearchBar()
            searchBar.text = query
            // the hits are the picture, not a keyboard sitting over them
            searchBar.resignFirstResponder()

            // Ready once the hits are drawn, not once they are asked for: the
            // call is asynchronous, and a picture taken in between is a picture
            // of the page unsearched.
            callSearch("odr.search", with: query) { [weak self] in
                guard let self else { return }

                ScreenshotMode.markReady(self.view)
            }

            return

        case .edit:
            // Entering an edit reloads the page as editable, so this comes back
            // here a second time - and that pass is the one worth photographing.
            guard document?.edit == true else {
                editDocument()

                return
            }

        default:
            break
        }

        ScreenshotMode.markReady(view)
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

        if let outcome = failureAwaitingTheScreen {
            failureAwaitingTheScreen = nil

            close(with: outcome)

            return
        }

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

    private func callSearch(
        _ function: String, with searchText: String, then finish: (() -> Void)? = nil
    ) {
        // an unescaped quote or backslash in the query would break the call
        // apart rather than search for itself
        let escaped =
            searchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        guard let webview else {
            finish?()

            return
        }

        webview.evaluateJavaScript("\(function)(\"\(escaped)\")") { _, error in
            if let error {
                CrashManager.shared.log(error)
            }

            finish?()
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
    func closeCurrentDocument(then finish: (() -> Void)? = nil) {
        document?.close()
        document = nil

        self.dismiss(animated: true, completion: finish)
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

    /// A page of ours rather than a document: the word "loading", or the error.
    /// The colour scheme is named because a web view paints a page that claims
    /// none white, whatever the reader has the device set to.
    private func loadMessage(_ body: String) {
        webview.loadHTMLString(
            "<html><head><meta name=\"color-scheme\" content=\"light dark\"></head><body>\(body)</body></html>",
            baseURL: nil)
    }

    func documentUpdateContent(_ doc: Document) {
        guard let url = doc.result else {
            documentNavigation = nil
            loadMessage("<h1>\(NSLocalizedString("loading", comment: ""))</h1>")

            return
        }

        // odrcore saw only a container, but the system knows this file as a
        // document of its own - an iWork one, which it draws properly and
        // odrcore has no reader for. The listing of the parts inside is what
        // the reader falls back to if the system cannot draw it after all.
        //
        // Nothing here names a format, and the day odrcore reads iWork the
        // file stops being an archive to it and this stops firing.
        if doc.isArchive, systemKnowsItAsADocument(doc.fileURL) {
            listingInReserve = url

            canEdit = false
            canSearch = false
            documentNavigation = webview.loadFileURL(doc.fileURL, allowingReadAccessTo: doc.fileURL)

            return
        }

        installFitToWidth(for: url)

        documentNavigation = self.webview.load(URLRequest(url: url))
    }

    /// Whether the system has a type of its own for this file that says it is a
    /// document rather than just a container. A `.pages` is composite content; a
    /// `.zip` and a `.jar` are not.
    private func systemKnowsItAsADocument(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }

        return !type.isDynamic && type.conforms(to: .compositeContent)
    }

    /// odrcore's listing of an archive, held back while the system is given the
    /// first go at the same file.
    private var listingInReserve: URL?

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
        let code = (error as NSError).code
        let isFromCore = (error as NSError).domain == CoreWrapperErrorDomain

        // The three ways a file does not open, and each has its own thing to
        // say. Only the last is worth a mail to us.
        let outcome: FailedToOpen
        switch (isFromCore, code) {
        case (true, CoreWrapperError.unsupportedFileType.rawValue):
            outcome = .unsupported
        case (true, CoreWrapperError.undecryptable.rawValue):
            // no password opens one of these, so asking for one would only ask again
            outcome = .locked
        default:
            outcome = .broken
        }

        giveUp(on: doc, with: outcome, code: code)
    }

    /// Nothing left to try with this file, so stop showing it: the document
    /// browser is a better answer than a page that will not appear, and the
    /// message comes up over it — the same way OpenDocument.droid ends here.
    ///
    /// Runs once. A page that fails after the document was already given up on
    /// would otherwise dismiss a reader that has gone.
    private func giveUp(on doc: Document, with outcome: FailedToOpen, code: Int) {
        guard !hasGivenUp else { return }
        hasGivenUp = true

        progressBar.isHidden = true
        documentNavigation = nil

        AnalyticsManager.shared.report(
            "load_error",
            parameters: [
                "code": code,
                AnalyticsConstants.paramItemName: doc.shortenedDocumentUrl,
                // attention: wrong for extensions like ".pages.zip"
                AnalyticsConstants.paramContentType: doc.fileURL.pathExtension.lowercased(),
            ])

        close(with: outcome)
    }

    /// Takes the reader off the screen and says why. The document is opened
    /// before this controller is presented, so a file that fails on the first
    /// try has nothing to dismiss and nowhere to put the message yet — it waits
    /// for the screen it is about to be given, the way the password prompt does.
    private func close(with outcome: FailedToOpen) {
        guard viewIfLoaded?.window != nil else {
            failureAwaitingTheScreen = outcome

            return
        }

        // taken before the dismiss, which is what takes this controller off it
        let host = presentingViewController

        closeCurrentDocument {
            (host ?? self).presentFailure(outcome)
        }
    }

    /// Whether this document has already ended in a message.
    private var hasGivenUp = false

    /// A message raised before this controller was on screen. Shown as soon as
    /// it is, rather than into a window hierarchy it is not part of.
    private var failureAwaitingTheScreen: FailedToOpen?

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

/// What to say about a file that did not open.
enum FailedToOpen {
    /// odrcore does not read this format at all.
    case unsupported
    /// A legacy Word, Excel or PowerPoint file no password opens.
    case locked
    /// odrcore took it and it still did not appear. This one asks to hear about it.
    case broken

    var message: String {
        switch self {
        case .unsupported: return NSLocalizedString("toast_error_illegal_file_reopen", comment: "")
        case .locked: return NSLocalizedString("toast_error_password_protected", comment: "")
        case .broken: return NSLocalizedString("dialog_broken_file", comment: "")
        }
    }

    /// Only a file odrcore accepted and then could not show is ours to hear about.
    var offersContact: Bool { self == .broken }
}

extension UIViewController {

    /// Says why a file did not open, and for the one case that is ours offers
    /// the way to tell us. Shown over the document browser rather than over the
    /// reader, which is gone by now.
    func presentFailure(_ outcome: FailedToOpen) {
        let alert = UIAlertController(
            title: NSLocalizedString("dialog_broken_file_title", comment: ""),
            message: outcome.message,
            preferredStyle: .alert)

        if outcome.offersContact {
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("action_contact", comment: ""), style: .default,
                    handler: { _ in Self.contactSupport() }))
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: ""), style: .cancel))

        present(alert, animated: true)

        if outcome.offersContact {
            AnalyticsManager.shared.report("contact_offer")
        }
    }

    /// A mail to us. Nothing more to say where there is no mail app: the
    /// address is in the message either way.
    private static func contactSupport() {
        AnalyticsManager.shared.report("contact_tapped")

        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = Constants.supportEmail
        mail.queryItems = [URLQueryItem(name: "subject", value: "OpenDocument Reader")]

        guard let url = mail.url else { return }

        UIApplication.shared.open(url)
    }
}
