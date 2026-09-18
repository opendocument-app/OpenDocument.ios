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
    SKStoreProductViewControllerDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    UIColorPickerViewControllerDelegate
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
    /// The bar and what hangs under it: the editing tools, the progress line.
    @IBOutlet weak var barStack: UIStackView!
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

    /// The document's name, sitting in the bar's empty middle.
    let documentTitleLabel = DocumentTitleLabel()
    private lazy var documentTitleItem = UIBarButtonItem(customView: documentTitleLabel)

    /// The bar as the storyboard has it, taken before anything is removed, since
    /// that is the only moment every button is there to be read.
    private lazy var toolBarItems: [UIBarButtonItem] = toolBar.items ?? []

    /// Whether the document on screen can be edited and searched. Neither button
    /// stays in the bar when it cannot be used.
    private var canEdit = false { didSet { updateToolBar() } }
    /// Whether the document is a pdf that takes marks. The same button as the
    /// pencil, with the highlighter for a glyph.
    private var canMark = false { didSet { updateEditButtonRole() } }
    /// The same slot the pencil sits in, showing the way out of the edit it
    /// started — as on OpenDocument.droid, where edit mode replaces the bar
    /// rather than emptying it.
    private var isEditingDocument = false {
        didSet {
            updateEditButtonRole()

            if !isEditingDocument {
                editToolBar.layout = nil
            }
        }
    }

    /// The row of tools under the bar while a document is edited.
    let editToolBar = EditToolBar()

    /// The colour the marks on a pdf take, until the reader picks another.
    private var markColor = UIColor(hex: EditToolBar.markColors[0].hex)

    /// Which menu the system colour picker was opened from.
    private var colorPickerTool: EditToolBar.Tool?

    /// Whether the Pro offer was shown during this edit, so a page full of
    /// refused line breaks raises it once.
    private var hasOfferedProForThisEdit = false

    /// How many formula cells the edits so far left out of date; said once
    /// each time the number grows.
    private var staleCells = 0
    private var canSearch = false {
        didSet {
            updateToolBar()

            if !canSearch {
                hideSearchBar()
            }
        }
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

            if isViewLoaded {
                updateDocumentTitle()
            }
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
        // the way back out of a file opened from a zip's listing
        webview.allowsBackForwardNavigationGestures = true

        searchBar.delegate = self
        searchBar.showsCancelButton = true
        searchBarHeightWhenShown = searchBar.heightAnchor.constraint(equalToConstant: 56)
        searchBarHeightWhenHidden = searchBar.heightAnchor.constraint(equalToConstant: 0)

        setUpEditToolBar()
        setUpPageMessages()

        setVCconstraints()
        hideSearchBar()

        // the chevron says where it goes; the words are for VoiceOver, which is
        // the one reader a glyph is no shorter for
        barButtonItem.accessibilityLabel = NSLocalizedString("back_to_documents", comment: "")
        updateEditButtonRole()

        setUpDocumentTitle()

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

    /// Only a link that leaves the page carries `target="_blank"`, and this app
    /// has no second window: the web goes to the browser, and what odrcore
    /// serves — should any of it arrive here — to the web view that asked.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        if CoreWrapper.isServedURL(url) {
            webView.load(navigationAction.request)
        } else if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }

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

        if !navigationResponse.canShowMIMEType {
            decisionHandler(.cancel)

            // the system could not draw it after all, so fall back to odrcore's
            if let page = corePageInReserve {
                corePageInReserve = nil

                documentNavigation = webview.load(URLRequest(url: page))

                return
            }

            giveUp(on: doc, with: .unsupported, code: 0)

            return
        }

        corePageInReserve = nil

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

    /// The page never arrived. Only what odrcore serves counts: a link out of a
    /// document that fails is the web's problem.
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

    /// Whether the reader stopped this load itself: turning a page cancels the
    /// one before it, and a response answered with `.cancel` lands here too.
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
            // ready once the tools are up, which `beginEditSession` says
            editDocument()

            return

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
        searchBar.topAnchor.constraint(equalTo: barStack.bottomAnchor, constant: Self.toolBarBottomMargin).isActive =
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
        } else if canMark, !Features.advancedEditing {
            offerPro(.pdf)
        } else {
            editDocument()
        }
    }

    // MARK: - the editing tools

    /// Under the bar and above the progress line, so it reads as part of the bar.
    private func setUpEditToolBar() {
        editToolBar.layout = nil
        editToolBar.advancedEditing = Features.advancedEditing
        editToolBar.onTap = { [weak self] tool in self?.editToolTapped(tool) }
        editToolBar.onChoice = { [weak self] tool, choice in self?.editToolChose(tool, choice) }

        barStack.insertArrangedSubview(editToolBar, at: 1)
    }

    /// Hears from the page: the log, a refusal, the style under the caret.
    private func setUpPageMessages() {
        let controller = webview.configuration.userContentController

        controller.add(WeakScriptMessageHandler(self), name: Self.pageMessageName)
        controller.addUserScript(
            WKUserScript(source: Self.pageMessageBridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    private static let pageMessageName = "odr"

    /// Points the page's callbacks at this controller. The page's own scripts
    /// have run by document end, so `odr` is there to be pointed.
    private static let pageMessageBridge = """
        (function () {
            if (typeof odr !== 'object' || !window.webkit || !webkit.messageHandlers.odr) { return; }
            var post = function (message) { webkit.messageHandlers.odr.postMessage(message); };
            odr.onEditChange = function (e) {
                post({ type: 'editChange', dirty: !!e.dirty, canUndo: !!e.canUndo, canRedo: !!e.canRedo });
            };
            odr.onEditRefused = function (e) {
                post({ type: 'editRefused', reason: String(e.reason || ''), message: String(e.message || '') });
            };
            odr.onSelectionChange = function (style) {
                post({ type: 'selection', style: style || {} });
            };
            odr.onCellsStale = function (detail) {
                post({ type: 'cellsStale', count: detail && detail.cells ? detail.cells.length : 0 });
            };
            if (!odr.annotation) { return; }
            // an armed tool marks a selection as it is made, which is what a
            // touch screen needs. The annotator has no callback of its own, so
            // the count of marks is reported after every gesture that can
            // change it; a mark settles 50ms after the pointer lifts
            odr.annotation.setOptions({ markOnSelection: true });
            var reported = -1;
            var reportMarks = function () {
                var count = odr.annotation.list().length;
                if (count === reported) { return; }
                reported = count;
                post({ type: 'marks', count: count });
            };
            var reportMarksSoon = function () { window.setTimeout(reportMarks, 120); };
            document.addEventListener('pointerup', reportMarksSoon);
            document.addEventListener('pointercancel', reportMarksSoon);
            document.addEventListener('selectionchange', reportMarksSoon);
            odr.reportMarks = reportMarks;
        })();
        """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        switch type {
        case "editChange":
            hasUnsavedEdits = body["dirty"] as? Bool ?? false
            editToolBar.setEnabled(.undo, body["canUndo"] as? Bool ?? false)
            editToolBar.setEnabled(.redo, body["canRedo"] as? Bool ?? false)

        case "marks":
            let count = body["count"] as? Int ?? 0
            hasUnsavedEdits = count > 0
            editToolBar.setEnabled(.undo, count > 0)

        case "cellsStale":
            if body["count"] as? Int ?? 0 > staleCells {
                showToast(controller: self, message: NSLocalizedString("edit_cells_stale", comment: ""), seconds: 3)
            }
            staleCells = body["count"] as? Int ?? 0

        case "editRefused":
            editRefused(reason: body["reason"] as? String ?? "")

        case "selection":
            let style = body["style"] as? [String: Any] ?? [:]
            editToolBar.setPressed(.bold, style["bold"] as? Bool ?? false)
            editToolBar.setPressed(.italic, style["italic"] as? Bool ?? false)
            editToolBar.setPressed(.underline, style["underline"] as? Bool ?? false)
            editToolBar.setPressed(.strikethrough, style["strikethrough"] as? Bool ?? false)

        default:
            break
        }
    }

    /// Turns the mode on in the page already on screen and shows its tools.
    /// A pdf needs no mode, only a marker that acts on a selection.
    private func beginEditSession() {
        hasOfferedProForThisEdit = false
        hasUnsavedEdits = false

        if document?.isAnnotatable == true {
            editToolBar.layout = .pdf
            editToolBar.setEnabled(.undo, false)
            run("odr.annotation.setColor(\(markColor.deviceRGB))")
            showToast(controller: self, message: NSLocalizedString("mark_hint", comment: ""), seconds: 2)
            editSessionReady()

            return
        }

        editToolBar.setEnabled(.undo, false)
        editToolBar.setEnabled(.redo, false)

        let isPlainText = document?.isPlainText == true

        webview.evaluateJavaScript("odr.editing.enable(); typeof odr.sheet === 'object'") { [weak self] isSheet, _ in
            guard let self, self.isEditingDocument else { return }

            self.editToolBar.layout = isPlainText || isSheet as? Bool == true ? .plain : .text
            self.editSessionReady()
        }
    }

    /// The tools are up, which is what a screenshot of an edit waits for.
    private func editSessionReady() {
        if ScreenshotMode.screen == .edit {
            ScreenshotMode.markReady(view)
        }
    }

    /// Whether the page holds edits or marks that only it has, which leaving
    /// would lose.
    private var hasUnsavedEdits = false

    private func editToolTapped(_ tool: EditToolBar.Tool) {
        if tool.isAdvanced, !Features.advancedEditing {
            offerPro(canMark ? .pdf : .formatting)

            return
        }

        switch tool {
        case .undo:
            run(canMark ? "odr.annotation.undo(); odr.reportMarks()" : "odr.editing.undo()")
        case .redo:
            run("odr.editing.redo()")
        case .bold, .italic, .underline, .strikethrough:
            run("odr.editing.toggle('\(tool.pageName ?? "")')")
        case .markHighlight, .markUnderline, .markStrikeOut, .markSquiggly, .markDraw:
            armMarker(tool)
        default:
            break
        }
    }

    /// As on the website: a selection is marked once and the tool stays down,
    /// the armed tool disarms, anything else arms.
    private func armMarker(_ tool: EditToolBar.Tool) {
        guard let name = tool.pageName else { return }

        let script = """
            (function () {
                var a = odr.annotation;
                var selection = window.getSelection();
                var selected = '\(name)' !== 'ink' && selection && !selection.isCollapsed;
                if (selected) {
                    var armed = a.getTool();
                    a.setTool('\(name)');
                    a.mark();
                    a.setTool(armed);
                    selection.removeAllRanges();
                    odr.reportMarks();
                    return armed;
                }
                if (a.getTool() === '\(name)') {
                    a.setTool(null);
                    return null;
                }
                a.setWidth(2);
                a.setTool('\(name)');
                return '\(name)';
            })()
            """

        webview.evaluateJavaScript(script) { [weak self] armed, error in
            if let error {
                CrashManager.shared.log(error)
            }

            self?.showArmedMarker(armed as? String)
        }
    }

    private func showArmedMarker(_ armed: String?) {
        for tool in EditToolBar.Layout.pdf.tools {
            editToolBar.setPressed(tool, tool.pageName != nil && tool.pageName == armed)
        }
    }

    private func editToolChose(_ tool: EditToolBar.Tool, _ choice: EditToolBar.Choice) {
        switch (tool, choice) {
        case (.fontSize, .size(let size)):
            run("odr.editing.format({ size: '\(size)pt' })")
        case (.textColor, .color(let hex)):
            run("odr.editing.format({ color: '\(hex ?? "")' })")
        case (.highlight, .color(let hex)):
            run("odr.editing.format({ highlight: \(hex.map { "'\($0)'" } ?? "null") })")
        case (.markColor, .color(let hex)):
            markColor = UIColor(hex: hex ?? EditToolBar.markColors[0].hex)
            run("odr.annotation.setColor(\(markColor.deviceRGB))")
        case (_, .customColor):
            colorPickerTool = tool

            let picker = UIColorPickerViewController()
            picker.delegate = self
            picker.supportsAlpha = false
            picker.selectedColor = tool == .markColor ? markColor : .label
            present(picker, animated: true)
        default:
            break
        }
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        guard let tool = colorPickerTool else { return }
        colorPickerTool = nil

        editToolChose(tool, .color(viewController.selectedColor.hexString))
    }

    /// The page said no. A line break or a format outside the paragraph is
    /// what Pro is for; the rest is said in a word.
    private func editRefused(reason: String) {
        if reason == "outOfScope", !Features.advancedEditing {
            guard !hasOfferedProForThisEdit else { return }
            hasOfferedProForThisEdit = true

            offerPro(.formatting)

            return
        }

        let key: String
        switch reason {
        case "newLine": key = "edit_refused_new_line"
        case "formula": key = "edit_refused_formula"
        case "formulaInput": key = "edit_refused_formula_input"
        case "rich", "shapes": key = "edit_refused_rich"
        case "readOnly": key = "edit_refused_read_only"
        case "range": key = "edit_refused_range"
        default: key = "edit_refused_generic"
        }

        AnalyticsManager.shared.report("edit_refused", parameters: ["reason": reason])

        showToast(controller: self, message: NSLocalizedString(key, comment: ""), seconds: 1.5)
    }

    /// What Pro adds, as the reader runs into it.
    enum ProFeature {
        case formatting
        case pdf

        var message: String {
            switch self {
            case .formatting: return NSLocalizedString("pro_feature_formatting", comment: "")
            case .pdf: return NSLocalizedString("pro_feature_pdf", comment: "")
            }
        }
    }

    /// Says what Pro is for, and leads to it. The Lite app's one gate.
    func offerPro(_ feature: ProFeature) {
        AnalyticsManager.shared.report("pro_gate_shown", parameters: ["feature": "\(feature)"])

        let alert = UIAlertController(
            title: NSLocalizedString("pro_feature_title", comment: ""),
            message: feature.message,
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: NSLocalizedString("not_now", comment: ""), style: .cancel))
        alert.addAction(
            UIAlertAction(title: NSLocalizedString("house_ad_cta_get_pro", comment: ""), style: .default) { _ in
                AnalyticsManager.shared.report("pro_gate_tapped", parameters: ["feature": "\(feature)"])

                self.openProOnAppStore()
            })

        present(alert, animated: true)
    }

    /// A script whose answer nobody needs.
    private func run(_ script: String) {
        webview.evaluateJavaScript(script) { _, error in
            if let error {
                CrashManager.shared.log(error)
            }
        }
    }

    /// A gap either side of the name, which is what puts it in the middle.
    private func setUpDocumentTitle() {
        // a glass capsule is what a button looks like, and this is not one
        if #available(iOS 26.0, *) {
            documentTitleItem.hidesSharedBackground = true
        }

        guard let back = toolBarItems.firstIndex(where: { $0 === barButtonItem }) else { return }

        toolBarItems.insert(
            contentsOf: [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                documentTitleItem,
            ],
            at: back + 1)

        updateDocumentTitle()
    }

    /// The name without its extension, as the document browser lists it.
    private func updateDocumentTitle() {
        documentTitleLabel.text = document?.fileURL.deletingPathExtension().lastPathComponent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateDocumentTitleWidth()
    }

    /// What the bar has left once its buttons have taken theirs.
    ///
    /// Measured against the view rather than the bar itself: on the first pass
    /// the bar still carries the width the storyboard drew it at, and the name
    /// keeps whatever width it is first measured at.
    private func updateDocumentTitleWidth() {
        let buttons = (toolBar.items ?? []).filter { $0.customView == nil && $0.image != nil }

        documentTitleLabel.maximumWidth =
            view.bounds.width - CGFloat(buttons.count) * Self.toolBarButtonWidth - Self.toolBarTitleGap
    }

    /// What one button takes of the bar. From iOS 26 a glass capsule with air
    /// around it, which is wider than the glyph older bars draw.
    private static var toolBarButtonWidth: CGFloat {
        if #available(iOS 26.0, *) {
            return 64
        }

        return 48
    }

    /// Kept clear either side of the name, so it never sits against a button.
    private static let toolBarTitleGap: CGFloat = 16

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
        canMark = document?.isAnnotatable ?? false
        canEdit = (document?.isEditable ?? false) || canMark
        isEditingDocument = document?.edit ?? false
    }

    /// A pencil to start an edit, a highlighter to mark a pdf, and the save
    /// glyph to write either. The label goes with it: VoiceOver reads that,
    /// not the glyph.
    private func updateEditButtonRole() {
        let symbol: String
        let label: String
        if isEditingDocument {
            symbol = "square.and.arrow.down"
            label = "action_edit_save"
        } else if canMark {
            symbol = "highlighter"
            label = "mark_pdf"
        } else {
            symbol = "pencil"
            label = "menu_edit"
        }

        editButton.image = UIImage(systemName: symbol)
        editButton.accessibilityLabel = NSLocalizedString(label, comment: "")
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

        if doc.edit, hasUnsavedEdits {
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

        // the system gets the first go, with odrcore's page kept in reserve
        if systemDrawsItBetter(doc) {
            corePageInReserve = url

            canEdit = false
            canMark = false
            canSearch = false
            documentNavigation = webview.loadFileURL(doc.fileURL, allowingReadAccessTo: doc.fileURL)

            return
        }

        documentNavigation = self.webview.load(URLRequest(url: url))
    }

    /// Three the system draws better, all falling back to `corePageInReserve`:
    /// html, which odrcore has no type for and reads as its own source, iWork,
    /// whose styles and pictures it does not read, and a container it knows as a
    /// document (`.epub` is composite content, `.zip` is not).
    private func systemDrawsItBetter(_ doc: Document) -> Bool {
        let ext = doc.fileURL.pathExtension.lowercased()

        guard let type = UTType(filenameExtension: ext), !type.isDynamic else { return false }

        return Self.webPageTypes.contains(where: type.conforms(to:))
            || Self.iWorkExtensions.contains(ext)
            || (doc.isArchive && type.conforms(to: .compositeContent))
    }

    /// Both, because `public.xhtml` conforms to xml rather than to html — and
    /// xml is what a flat ODF is, which odrcore does render.
    private static let webPageTypes: [UTType] = [.html, UTType("public.xhtml")].compactMap { $0 }

    private static let iWorkExtensions: Set<String> = ["pages", "numbers", "key"]

    /// odrcore's page, held back while the system has the first go.
    private var corePageInReserve: URL?

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

    /// Nothing left to try: close the reader and say why. Runs once, so a page
    /// failing afterwards cannot dismiss a reader that has gone.
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

    /// Dismisses the reader and shows the message over the browser. A file that
    /// fails before this controller is on screen waits for the screen.
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

    /// A message raised before this controller was on screen.
    private var failureAwaitingTheScreen: FailedToOpen?

    func documentLoadingStarted(_ doc: Document) {
        progressBar.isHidden = false
        progressBar.observedProgress = doc.loadProgress

        // neither is known until the page it produces is loaded
        canEdit = false
        canMark = false
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

    func documentEditingStarted(_ doc: Document) {
        isEditingDocument = true
        beginEditSession()
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
    /// odrcore took it and it still did not appear.
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

    /// Says why a file did not open, and offers the way to tell us where that helps.
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

/// The web view's content controller holds its handlers strongly, and this
/// controller holds the web view: a weak step in between breaks the cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var handler: WKScriptMessageHandler?

    init(_ handler: WKScriptMessageHandler) {
        self.handler = handler
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}
