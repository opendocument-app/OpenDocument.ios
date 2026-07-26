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
    case backTranslate
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
            // every page of the document already has an address, so turning to
            // one is picking a URL rather than translating the file again
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
    private var wasPageCountAnnounced = false

    override init(fileURL url: URL) {
        super.init(fileURL: url)
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        parse()
    }

    func parse() {
        delegate?.documentLoadingStarted(self)

        loadProgress.completedUnitCount = 2

        result = nil
        pageURLs = nil
        delegate?.documentUpdateContent(self)

        let cachePath = URL(fileURLWithPath: NSTemporaryDirectory())
        let outputPath = URL(fileURLWithPath: NSTemporaryDirectory())

        do {
            try coreWrapper.translate(
                fileURL.path,
                cache: cachePath.path,
                into: outputPath.path,
                with: password,
                editable: edit
            )
        } catch let error as NSError
            where error.domain == CoreWrapperErrorDomain
            && error.code == CoreWrapperError.wrongPassword.rawValue
        {
            delegate?.documentEncrypted(self)

            return
        } catch {
            delegate?.documentLoadingError(self, error: error)

            return
        }

        isOdf = true

        loadProgress.completedUnitCount = loadProgress.totalUnitCount

        // translate only reports success once it has at least one page
        pageURLs = coreWrapper.pageURLs
        pageNames = coreWrapper.pageNames

        showPage()

        if !wasPageCountAnnounced {
            delegate?.documentPagesChanged(self)

            wasPageCountAnnounced = true
        }

        delegate?.documentLoadingCompleted(self)
    }

    /// Shows the currently selected page, clamped to what the document has:
    /// switching to page five of a spreadsheet and then editing it into four
    /// sheets should not walk off the end.
    private func showPage() {
        guard let pageURLs, !pageURLs.isEmpty else { return }

        result = pageURLs[min(max(page, 0), pageURLs.count - 1)]

        delegate?.documentUpdateContent(self)
    }

    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        CrashManager.shared.log(error)
    }

    override func writeContents(
        _ contents: Any, to url: URL, for saveOperation: UIDocument.SaveOperation, originalContentsURL: URL?
    ) throws {
        let diff = try generateDiff()

        // CoreWrapper is guarded by @synchronized, but the document handle it
        // holds is only valid together with the web view that produced the diff,
        // so the call stays on the main thread
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

    /// Asks the web view for the edits the user made. Runs on the main thread
    /// and blocks the calling save thread until the JavaScript call comes back.
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
                // signalled on every path, including the ones that used to leave
                // the dispatch group unbalanced and fall into the 30s timeout
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

    var shortenedDocumentUrl: String {
        return fileURL.absoluteString.prefix(49) + ".." + fileURL.absoluteString.suffix(49)
    }
}
