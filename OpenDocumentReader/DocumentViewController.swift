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

    /// The bar as the storyboard has it, taken before anything is removed, since
    /// that is the only moment every button is there to be read.
    private lazy var toolBarItems: [UIBarButtonItem] = toolBar.items ?? []

    /// Whether the document on screen can be edited and searched. Neither button
    /// stays in the bar when it cannot be used.
    var canEdit = false { didSet { updateToolBar() } }
    /// Whether the document is a pdf that takes marks.
    private var canMark = false {
        didSet {
            updateEditButtonRole()
            updateToolBar()
        }
    }
    private var isEditingDocument = false {
        didSet {
            updateEditButtonRole()
            updateToolBar()

            if !isEditingDocument {
                editToolBar.layout = nil
            }
        }
    }

    /// Takes the last edit back. Only in the bar while editing.
    lazy var undoButton: UIBarButtonItem = makeEditButton(
        symbol: "arrow.uturn.backward", label: "edit_undo", action: #selector(undoTapped(_:)))

    /// Puts it back. Not over a pdf - see ``updateToolBar()``.
    lazy var redoButton: UIBarButtonItem = makeEditButton(
        symbol: "arrow.uturn.forward", label: "edit_redo", action: #selector(redoTapped(_:)))

    /// Saves the edit, and stays in it. Only in the bar while editing.
    lazy var saveButton: UIBarButtonItem = makeEditButton(
        symbol: "square.and.arrow.down", label: "action_edit_save", action: #selector(saveTapped(_:)))

    /// The bar holds what is done to the document; the strip what is done to
    /// the text. All three start off: a fresh page has nothing to write.
    private func makeEditButton(symbol: String, label: String, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
        item.accessibilityLabel = NSLocalizedString(label, comment: "")
        item.isEnabled = false

        return item
    }

    private func makeSpacer() -> UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        item.width = 10

        return item
    }

    private lazy var undoButtonSpacer: UIBarButtonItem = makeSpacer()
    private lazy var redoButtonSpacer: UIBarButtonItem = makeSpacer()
    private lazy var saveButtonSpacer: UIBarButtonItem = makeSpacer()

    /// The strip of tools under the bar while a document is edited.
    let editToolBar = EditToolBar()

    /// The colour each marker on a pdf takes, until the reader picks another.
    private var markColors: [EditToolBar.Tool: UIColor] = [:]

    /// The colour the highlight button turns on; the selection's own where it
    /// has one.
    private var highlightColor = UIColor(hex: EditToolBar.highlightColors[0].hex)

    /// Whether the selection shows a highlight, as the page last said.
    private var selectionHasHighlight = false

    /// Which menu the system colour picker was opened from.
    private var colorPickerTool: EditToolBar.Tool?

    /// Whether the Pro offer was shown during this edit, so it shows once.
    private var hasOfferedProForThisEdit = false

    /// How many formula cells the edits so far left out of date; said each
    /// time the number grows.
    private var staleCells = 0

    /// Set by a save, so the page that loads next is put back into the mode.
    private var resumesEditAfterLoad = false
    var canSearch = false {
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

        setUpEditButtons()
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

        // a save renders the file again, and the edit goes on in the new page
        if let documentNavigation, navigation === documentNavigation, resumesEditAfterLoad {
            resumesEditAfterLoad = false

            if document?.edit == true {
                beginEditSession()
            }
        }

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
    /// height, which whatever is pinned to either edge would cut off. Older
    /// bars have a background of their own and want no such gap.
    private static var toolBarMargin: CGFloat {
        if #available(iOS 26.0, *) {
            return 8
        }

        return 0
    }

    /// What the bar takes. A capsule is drawn to the bar's height, so a bar
    /// sized to the glyph alone leaves them touching both edges.
    private static var toolBarHeight: CGFloat {
        if #available(iOS 26.0, *) {
            return 50
        }

        return 44
    }

    func setVCconstraints() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        bannerSlot.translatesAutoresizingMaskIntoConstraints = false
        pageTabBar.translatesAutoresizingMaskIntoConstraints = false
        webview.translatesAutoresizingMaskIntoConstraints = false

        // above everything, the bar included: under it the banner stood
        // between the tools and the page they act on
        bannerSlot.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        bannerSlot.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        bannerSlot.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        // no height here: that is bannerSlotHeight from the storyboard, which
        // hideBannerSlot zeroes, and a second one would fight it

        barStack.topAnchor.constraint(equalTo: bannerSlot.bottomAnchor, constant: Self.toolBarMargin).isActive = true
        toolBar.heightAnchor.constraint(equalToConstant: Self.toolBarHeight).isActive = true

        searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        searchBar.topAnchor.constraint(equalTo: barStack.bottomAnchor, constant: Self.toolBarMargin).isActive =
            true

        // under the search bar, which is why the tab bar is not in the tool
        // bar's stack: an arranged subview is placed by the stack, and these
        // would be a second answer to the same question
        pageTabBar.topAnchor.constraint(equalTo: searchBar.bottomAnchor).isActive = true
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

    /// The pen: turns the mode on, and off again. Leaving with changes the
    /// page alone holds asks first.
    ///
    /// It stands on the core's answer, and every edition opens what it names.
    /// What Lite does not sell is the tool - see ``editToolTapped(_:)``.
    @IBAction func toggleEdit(_ sender: UIBarButtonItem) {
        if isEditingDocument {
            leaveEdit()
        } else {
            editDocument()
        }
    }

    /// Without changes the page on screen is the file, so the mode only goes
    /// off. With them: save, discard, or stay.
    func leaveEdit() {
        guard hasUnsavedEdits else {
            document?.endEdit(renderingAgain: false)

            return
        }

        AnalyticsManager.shared.report("show_alert_unsaved_changes")

        let alert = UIAlertController(
            title: NSLocalizedString("alert_unsaved_changes", comment: ""),
            message: NSLocalizedString("alert_save_now", comment: ""), preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("no", comment: ""), style: .destructive,
                handler: { _ in
                    AnalyticsManager.shared.report("alert_unsaved_changes_no")

                    self.discardChanges()
                }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("yes", comment: ""), style: .default,
                handler: { _ in
                    AnalyticsManager.shared.report("alert_unsaved_changes_yes")

                    // the file holds the edit once it is written, so leaving
                    // reads back what was saved
                    self.saveContent { success in
                        guard success else { return }

                        self.document?.endEdit(renderingAgain: true)
                    }
                }))

        present(alert, animated: true)
    }

    /// Saves, and stays in the edit.
    @objc func saveTapped(_ sender: UIBarButtonItem) {
        saveAndStay()
    }

    /// A pdf keeps its marks in the annotator, not in the editor.
    @objc func undoTapped(_ sender: UIBarButtonItem) {
        AnalyticsManager.shared.report("menu_edit_undo")

        run(canMark ? "odr.annotation.undo()" : "odr.editing.undo()")
    }

    @objc func redoTapped(_ sender: UIBarButtonItem) {
        AnalyticsManager.shared.report("menu_edit_redo")

        run("odr.editing.redo()")
    }

    func saveAndStay(completion: ((Bool) -> Void)? = nil) {
        saveContent { success in
            if success {
                self.resumesEditAfterLoad = true
                self.document?.reload()
            }

            completion?(success)
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

    /// Points the page's callbacks at this controller. It runs at document
    /// end, after the page's own scripts.
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
            // asked of the page, since only a sheet carries that editor. The
            // pointer is no use: a web view answers it as a mouse
            if (odr.editing && odr.editing.setSheetOptions) {
                odr.editing.setSheetOptions({ editOnClick: true });
            }
            if (!odr.annotation) { return; }
            // an armed tool marks each selection as it is made: a tap elsewhere
            // would lose it
            odr.annotation.setOptions({ markOnSelection: true });
            odr.onAnnotationChange = function (e) {
                post({ type: 'marks', count: e && e.count ? e.count : 0 });
            };
        })();
        """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        switch type {
        case "editChange":
            hasUnsavedEdits = body["dirty"] as? Bool ?? false
            undoButton.isEnabled = body["canUndo"] as? Bool ?? false
            redoButton.isEnabled = body["canRedo"] as? Bool ?? false

        case "marks":
            let count = body["count"] as? Int ?? 0
            hasUnsavedEdits = count > 0
            undoButton.isEnabled = count > 0

        case "cellsStale":
            let count = body["count"] as? Int ?? 0
            if count > staleCells {
                let message = String.localizedStringWithFormat(
                    NSLocalizedString("edit_cells_stale", comment: ""), count)
                showToast(controller: self, message: message, seconds: 3)
            }
            staleCells = count

        case "editRefused":
            editRefused(reason: body["reason"] as? String ?? "")

        case "selection":
            let style = body["style"] as? [String: Any] ?? [:]
            editToolBar.setPressed(.bold, style["bold"] as? Bool ?? false)
            editToolBar.setPressed(.italic, style["italic"] as? Bool ?? false)
            editToolBar.setPressed(.underline, style["underline"] as? Bool ?? false)
            editToolBar.setPressed(.strikethrough, style["strikethrough"] as? Bool ?? false)

            // the bars and the size follow the selection, as the website's do
            if let color = style["color"] as? String {
                editToolBar.setColor(.textColor, UIColor(hex: color))
            }
            let highlight = style["highlight"] as? String
            selectionHasHighlight = highlight != nil
            editToolBar.setPressed(.highlight, selectionHasHighlight)
            if let highlight {
                highlightColor = UIColor(hex: highlight)
                editToolBar.setColor(.highlight, highlightColor)
            }
            editToolBar.setFontSize(
                (style["size"] as? String).map { $0.hasSuffix("pt") ? String($0.dropLast(2)) : $0 })

        default:
            break
        }
    }

    /// Turns the mode on in the page already on screen and shows its tools. A
    /// sheet or a plain text file takes no formatting, so it gets no strip.
    private func beginEditSession() {
        hasOfferedProForThisEdit = false
        hasUnsavedEdits = false
        staleCells = 0
        selectionHasHighlight = false
        isEditSessionReady = false
        undoButton.isEnabled = false
        redoButton.isEnabled = false

        if document?.isAnnotatable == true {
            editToolBar.layout = .pdf
            for tool in EditToolBar.Layout.pdf.tools where tool.showsColor {
                editToolBar.setColor(tool, markColor(of: tool))
            }
            showToast(controller: self, message: NSLocalizedString("mark_hint", comment: ""), seconds: 2)
            editSessionReady()

            return
        }

        let isPlainText = document?.isPlainText == true

        webview.evaluateJavaScript("odr.editing.enable(); typeof odr.sheet === 'object'") { [weak self] isSheet, _ in
            guard let self, self.isEditingDocument else { return }

            let formats = !isPlainText && isSheet as? Bool != true
            self.editToolBar.layout = formats ? .text : nil
            if formats {
                self.editToolBar.setColor(.highlight, self.highlightColor)
            }
            self.editSessionReady()
        }
    }

    /// Whether the page has said what it is. Not the strip itself: a sheet
    /// answers with no strip at all.
    private(set) var isEditSessionReady = false

    /// The tools are up, which is what a screenshot of an edit waits for.
    private func editSessionReady() {
        isEditSessionReady = true

        if ScreenshotMode.screen == .edit {
            ScreenshotMode.markReady(view)
        }
    }

    /// Whether the page holds edits or marks that only it has, which leaving
    /// would lose.
    private var hasUnsavedEdits = false {
        didSet {
            saveButton.isEnabled = hasUnsavedEdits
        }
    }

    /// The gate is on the tool, not the mode: what Lite does not sell offers
    /// Pro, and the highlighter beside it works in every edition.
    private func editToolTapped(_ tool: EditToolBar.Tool) {
        if !tool.isFree, !Features.advancedEditing {
            offerPro(canMark ? .pdf : .formatting)

            return
        }

        switch tool {
        case .bold, .italic, .underline, .strikethrough:
            run("odr.editing.toggle('\(tool.pageName ?? "")')")
        case .highlight:
            // off where the selection shows one, else on in the current colour
            run(
                "odr.editing.format({ highlight: \(selectionHasHighlight ? "null" : "'\(highlightColor.hexString)'") })"
            )
        case .markHighlight, .markUnderline, .markStrikeOut, .markSquiggly, .markDraw:
            pressMarker(tool, recolor: false)
        default:
            break
        }
    }

    private func markColor(of tool: EditToolBar.Tool) -> UIColor {
        markColors[tool] ?? UIColor(hex: tool.defaultColor ?? EditToolBar.markColors[0].hex)
    }

    /// A tap on a marker, or a new colour for it (`recolor`).
    private func pressMarker(_ tool: EditToolBar.Tool, recolor: Bool) {
        guard let name = tool.pageName else { return }

        let script =
            "odr.annotation.\(recolor ? "recolor" : "press")('\(name)', { color: \(markColor(of: tool).deviceRGB), width: 2 })"

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
            // a colour becomes the one the button turns on; none takes it off
            if let hex {
                highlightColor = UIColor(hex: hex)
                editToolBar.setColor(.highlight, highlightColor)
            }
            run("odr.editing.format({ highlight: \(hex.map { "'\($0)'" } ?? "null") })")
        case (.markHighlight, .color(let hex)), (.markUnderline, .color(let hex)),
            (.markStrikeOut, .color(let hex)), (.markSquiggly, .color(let hex)), (.markDraw, .color(let hex)):
            markColors[tool] = UIColor(hex: hex ?? tool.defaultColor ?? EditToolBar.markColors[0].hex)
            editToolBar.setColor(tool, markColor(of: tool))
            pressMarker(tool, recolor: true)
        case (_, .customColor):
            colorPickerTool = tool

            let picker = UIColorPickerViewController()
            picker.delegate = self
            picker.supportsAlpha = false
            switch tool {
            case .highlight: picker.selectedColor = highlightColor
            case .textColor: picker.selectedColor = .label
            default: picker.selectedColor = markColor(of: tool)
            }
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

    /// The page refused an edit. In Lite, an edit out of scope offers Pro.
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

    /// What is done to the document goes after the pen: undo, redo, save.
    private func setUpEditButtons() {
        guard let pen = toolBarItems.firstIndex(where: { $0 === editButtonSpacer }) else { return }

        toolBarItems.insert(
            contentsOf: [undoButton, undoButtonSpacer, redoButton, redoButtonSpacer, saveButton, saveButtonSpacer],
            at: pen + 1)
    }

    /// On the bar rather than in it: a bar item pushes the buttons aside, and
    /// the name has to give way to them instead.
    private func setUpDocumentTitle() {
        toolBar.addSubview(documentTitleLabel)

        updateDocumentTitle()
    }

    /// The name without its extension, as the document browser lists it.
    private func updateDocumentTitle() {
        documentTitleLabel.text = document?.fileURL.deletingPathExtension().lastPathComponent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        layOutDocumentTitle()
    }

    /// The name takes what the buttons leave between the back button and the
    /// rest. The bar does not say where it put a button, so the room is
    /// counted from how many there are.
    private func layOutDocumentTitle() {
        let buttons = (toolBar.items ?? []).filter { $0.image != nil }
        let start = Self.toolBarButtonWidth + Self.toolBarTitleGap
        let end = toolBar.bounds.width - CGFloat(buttons.count - 1) * Self.toolBarButtonWidth - Self.toolBarTitleGap

        documentTitleLabel.frame = CGRect(
            x: start, y: 0, width: max(0, end - start), height: toolBar.bounds.height)
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

    /// While an edit is on the bar is the edit's: undo, redo and save join it,
    /// and the magnifier and the name stand down - six buttons and a name do
    /// not fit a phone's bar. A pdf mark is never put back, so redo stays out.
    private func updateToolBar() {
        documentTitleLabel.isHidden = isEditingDocument
        view.setNeedsLayout()

        toolBar.items = toolBarItems.filter { item in
            if item === editButton || item === editButtonSpacer {
                return canEdit
            }
            if item === redoButton || item === redoButtonSpacer {
                return canEdit && isEditingDocument && !canMark
            }
            if item === undoButton || item === undoButtonSpacer || item === saveButton
                || item === saveButtonSpacer
            {
                return canEdit && isEditingDocument
            }
            if item === searchButton || item === searchButtonSpacer {
                return canSearch && !isEditingDocument
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

    /// The pencil, for a document and a pdf alike: the two never stand in the
    /// bar together, so the label separates them. Selected while the mode is
    /// on.
    private func updateEditButtonRole() {
        editButton.image = UIImage(systemName: "pencil")
        editButton.accessibilityLabel = NSLocalizedString(canMark ? "mark_pdf" : "menu_edit", comment: "")
        editButton.isSelected = isEditingDocument
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

    func documentEditingEnded(_ doc: Document) {
        run(
            "if (window.odr) { if (odr.editing) { odr.editing.disable(); } if (odr.annotation) { odr.annotation.setTool(null); } }"
        )
        view.endEditing(true)
        isEditingDocument = false
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
