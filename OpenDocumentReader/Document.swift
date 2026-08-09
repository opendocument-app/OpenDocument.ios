import UIKit
import WebKit

protocol DocumentDelegate: AnyObject {
    func documentUpdateContent(_ doc: Document)
    func documentEncrypted(_ doc: Document)
    func documentLoadingError(_ doc: Document, error: Error)
    func documentLoadingStarted(_ doc: Document)
    func documentLoadingCompleted(_ doc: Document)
    func documentPagesChanged(_ doc: Document)
}

enum DocumentError: Error {
    case getHtml
    /// odrcore accepted the document but could not serve one of its pages.
    case pageNotServed
}

class Document: UIDocument {

    public var result: URL?
    public var pageNames: [String]?
    public var pageURLs: [URL]?

    public weak var delegate: DocumentDelegate?
    public var loadProgress = Progress(totalUnitCount: 5)

    private var coreWrapper = CoreWrapper()

    public var page: Int = 0 {
        didSet {
            // every page already has an address, so turning to one picks a URL
            // rather than translating the file again
            showPage()
        }
    }
    public var password: String? {
        didSet {
            parse()
        }
    }
    public var edit = false {
        didSet {
            parse()
        }
    }

    public var webview: WKWebView?

    public var isOdf = false
    /// Whether the menu should offer to edit this one - see `CoreWrapper.isEditable`.
    public var isEditable = false
    private var wasPageCountAnnounced = false

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        parse()
    }

    func parse() {
        notify { $0.documentLoadingStarted(self) }

        loadProgress.completedUnitCount = 2

        isOdf = false
        isEditable = false
        result = nil
        pageURLs = nil
        notify { $0.documentUpdateContent(self) }

        let temporaryDirectory = NSTemporaryDirectory()

        do {
            try coreWrapper.translate(
                fileURL.path,
                cache: temporaryDirectory,
                into: temporaryDirectory,
                with: password,
                editable: edit
            )
        } catch let error as NSError
            where error.domain == CoreWrapperErrorDomain
            && error.code == CoreWrapperError.wrongPassword.rawValue
        {
            notify { $0.documentEncrypted(self) }

            return
        } catch {
            notify { $0.documentLoadingError(self, error: error) }

            return
        }

        isOdf = true
        isEditable = coreWrapper.isEditable

        loadProgress.completedUnitCount = loadProgress.totalUnitCount

        // translate only reports success once it has at least one page
        pageURLs = coreWrapper.pageURLs
        pageNames = coreWrapper.pageNames

        showPage()

        if !wasPageCountAnnounced {
            notify { $0.documentPagesChanged(self) }

            wasPageCountAnnounced = true
        }

        notify { $0.documentLoadingCompleted(self) }
    }

    /// Clamped to what the document has: switching to page five of a
    /// spreadsheet and then editing it into four sheets should not walk off the
    /// end.
    private func showPage() {
        guard let pageURLs, !pageURLs.isEmpty else { return }

        result = pageURLs[min(max(page, 0), pageURLs.count - 1)]

        notify { $0.documentUpdateContent(self) }
    }

    /// UIDocument reads on a background queue, so `load(fromContents:)` — and
    /// with it everything `parse` reports — arrives off the main thread. Runs
    /// inline when already there, so setting `page` or `edit` still updates the
    /// view before returning.
    private func notify(_ body: @escaping (DocumentDelegate) -> Void) {
        guard !Thread.isMainThread else {
            if let delegate {
                body(delegate)
            }

            return
        }

        DispatchQueue.main.async {
            if let delegate = self.delegate {
                body(delegate)
            }
        }
    }

    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        CrashManager.shared.log(error)
    }

    override func writeContents(
        _ contents: Any, to url: URL, for saveOperation: UIDocument.SaveOperation, originalContentsURL: URL?
    ) throws {
        let diff = try generateDiff()

        // the document handle CoreWrapper holds is only valid together with the
        // web view that produced the diff, so the edit stays on the main thread
        try onMainThread {
            try coreWrapper.backTranslate(diff, into: url.path)
        }
    }

    /// UIDocument calls writeContents off the main thread, but hopping to main
    /// unconditionally would deadlock if that ever changes.
    private func onMainThread<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try work()
        }

        return try DispatchQueue.main.sync(execute: work)
    }

    /// Blocks the calling save thread until the web view has handed back the
    /// edits the user made.
    private func generateDiff() throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error> = .failure(DocumentError.getHtml)

        DispatchQueue.main.async {
            guard let webview = self.webview else {
                result = .failure(DocumentError.getHtml)
                semaphore.signal()

                return
            }

            webview.evaluateJavaScript("odr.generateDiff()") { value, error in
                defer { semaphore.signal() }

                if let error {
                    CrashManager.shared.log(error)
                    result = .failure(error)

                    return
                }

                guard let diff = value as? String else {
                    result = .failure(DocumentError.getHtml)

                    return
                }

                result = .success(diff)
            }
        }

        guard semaphore.wait(timeout: .now() + 30) == .success else {
            throw DocumentError.getHtml
        }

        return try result.get()
    }
}

extension Document {

    /// Elided in the middle, because the interesting part of a container path is
    /// at both ends and analytics only takes so much.
    var shortenedDocumentUrl: String {
        let url = fileURL.absoluteString

        guard url.count > 100 else { return url }

        return url.prefix(49) + ".." + url.suffix(49)
    }
}
