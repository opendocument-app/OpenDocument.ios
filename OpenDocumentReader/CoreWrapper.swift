import Foundation
import OdrCore
import OdrCoreObjC

let CoreWrapperErrorDomain = "app.opendocument.CoreWrapperErrorDomain"

@objc enum CoreWrapperError: Int {
    case unknown = 1
    case wrongPassword = 2
    /// Not something odrcore renders for us — see the guard in `translate`.
    case unsupportedFileType = 3
    /// Locked, and odrcore has no way in whatever the password — a legacy Word,
    /// Excel or PowerPoint file.
    case undecryptable = 4
}

private func coreWrapperError(_ code: CoreWrapperError, _ description: String) -> NSError {
    NSError(
        domain: CoreWrapperErrorDomain, code: code.rawValue,
        userInfo: [NSLocalizedDescriptionKey: description])
}

/// The one server the app has, brought up on first use and left running.
private final class PageServer {
    static let shared = PageServer()

    private let lock = NSLock()
    private var server: HttpServer?
    private var handle: HttpServer.ServerHandle?
    private var translation: UInt64 = 0

    var port: UInt32 { lock.withLock { handle?.port ?? 0 } }

    /// Connects `service` and returns the base URL its views are served under.
    /// Nil if the socket could not be opened.
    ///
    /// A fresh prefix every time, because the web view caches by URL:
    /// re-translating after a password or an edit has to end up at an address it
    /// has not seen.
    func connect(_ service: HtmlService) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        if server == nil {
            let server = HttpServer()
            guard let handle = try? server.serve() else { return nil }
            self.server = server
            self.handle = handle
        }
        guard let server, let handle else { return nil }

        translation += 1
        let prefix = "odr\(translation)"

        // drops the service of the document shown before this one, whose pages
        // nobody is going to ask for again
        try? server.clear()
        guard (try? server.connect(service, prefix: prefix)) != nil else { return nil }

        return handle.url(prefix: prefix)
    }
}

/// The view odrcore names "document" holds the whole file in one page: every
/// slide of a presentation, every page of a PDF, the entire text document.
private func isCombinedView(_ view: HtmlView) -> Bool { view.name == "document" }

/// The views to show as pages, the same way OpenDocument.droid picks them: a tab
/// per sheet for spreadsheets, and for everything else the combined view alone,
/// which already holds every slide or page.
private func selectViews(_ views: [HtmlView], _ documentType: DocumentType) -> [HtmlView] {
    let isSpreadsheet = documentType == .spreadsheet
    let hasCombinedView = views.contains(where: isCombinedView)

    return views.filter { view in
        isSpreadsheet ? !isCombinedView(view) : (!hasCombinedView || isCombinedView(view))
    }
}

@objc final class CoreWrapper: NSObject {
    @objc private(set) var pageNames: [String] = []
    @objc private(set) var pageURLs: [URL] = []

    /// Whether odrcore saw only a container, so the page is a listing of what is inside it.
    @objc private(set) var isArchive = false

    /// Whether `backTranslate` has a document to apply an edit to. Only a
    /// document that said it takes one is kept, so having it *is* the answer.
    @objc var isEditable: Bool { lock.withLock { document != nil } }

    private var document: OdrCoreObjC.Document?
    private let lock = NSRecursiveLock()

    /// The largest sheet region translated, as on OpenDocument.droid. The
    /// encoding is written out because Swift has no `@encode`.
    private static let spreadsheetLimit: NSValue = withUnsafeBytes(
        of: TableDimensions(rows: 100_000, columns: 500)
    ) { NSValue(bytes: $0.baseAddress!, objCType: "{ODRTableDimensions=II}") }

    /// Bounds the rows by the sheet's width: the wider, the fewer it keeps.
    private static let spreadsheetCellLimit: UInt64 = 500_000

    @objc func translate(
        _ inputPath: String,
        cache cachePath: String,
        into outputPath: String,
        with password: String?,
        editable: Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        pageNames = []
        pageURLs = []
        document = nil
        isArchive = false

        let fileTypes = (try? DecodedFile.listFileTypes(path: inputPath)) ?? []
        guard !fileTypes.isEmpty else {
            throw coreWrapperError(.unsupportedFileType, "odrcore does not recognise this file type")
        }

        var file = try DecodedFile.decode(path: inputPath)
        if file.isPasswordEncrypted {
            do {
                file = try file.decrypt(withPassword: password ?? "")
            } catch let error as NSError
                where error.code == ODRError.wrongPassword.rawValue
            {
                throw coreWrapperError(.wrongPassword, "wrong password")
            } catch let error as NSError
                where error.code == ODRError.unsupportedOperation.rawValue
            {
                throw coreWrapperError(.undecryptable, "odrcore cannot decrypt this format")
            }
        }

        guard Odr.capabilities(fileType: file.fileType).translateHtml else {
            throw coreWrapperError(.unsupportedFileType, "odrcore does not render this file type")
        }

        // the same answers OpenDocument.droid gives odrcore, so a document is
        // the same document on both — the viewport meta each page carries is
        // decided from these
        let config = HtmlConfig()
        config.editable = editable
        // resource paths are resolved relative to an output directory, and in
        // server mode there is none — odrcore rejects the combination
        config.relativeResourcePaths = false
        // the side margins of a printed page, which is what it was written to
        // look like, and what makes odrcore call a text document paged: its
        // pages are then fitted to the screen rather than shown at full size
        config.textDocumentMargin = true
        // the reader's own appearance: odrcore writes a dark sheet behind a
        // `prefers-color-scheme: dark`, which the web view answers from the
        // system setting. A pdf has no dark view and stays light.
        config.colorScheme = .system
        // served with the pages rather than inlined as base64
        config.embedImages = false
        // odrcore's own css and js go into the page: there is no output
        // directory to put them beside
        config.embedShippedResources = true
        // a WKWebView fits no top-level document, so the view fits itself
        config.viewportMode = .fitWidthByView
        // stated rather than inherited: a sheet past the limit is cut off silently
        config.spreadsheetLimit = Self.spreadsheetLimit
        config.spreadsheetCellLimit = NSNumber(value: Self.spreadsheetCellLimit)
        config.spreadsheetLimitByContent = true

        let documentType: DocumentType
        let openedDocument: OdrCoreObjC.Document?
        let service: HtmlService

        if file.isDocumentFile {
            let documentFile = try file.asDocumentFile()
            let document = try documentFile.document()

            documentType = documentFile.documentType
            // the document's own answer: a format odrcore renders but cannot write
            // back would otherwise offer Edit and fail at the save
            openedDocument = document.isEditable && document.isSavable ? document : nil
            service = try HtmlTranslator.translate(
                document: document, cachePath: cachePath, config: config)
        } else {
            // nothing to edit, and `.unknown` keeps the single view each of
            // these has - `.spreadsheet` would ask for a tab per sheet
            documentType = .unknown
            openedDocument = nil
            service = try HtmlTranslator.translate(
                file: file, cachePath: cachePath, config: config)
        }

        let views = selectViews(service.views, documentType)
        guard !views.isEmpty else {
            throw coreWrapperError(.unknown, "odrcore produced no displayable page")
        }

        guard let base = PageServer.shared.connect(service) else {
            throw coreWrapperError(.unknown, "could not serve the translated document")
        }

        // only once nothing can throw any more: backTranslate must not be handed
        // a document whose pages were never served
        self.document = openedDocument

        isArchive = file.isArchiveFile
        pageNames = views.map(\.name)
        pageURLs = views.map { base.appendingPathComponent($0.path) }
    }

    @objc func backTranslate(_ diff: String, into outputPath: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let document else {
            throw coreWrapperError(.unknown, "no document has been translated yet")
        }

        try HtmlTranslator.edit(document: document, diff: diff)

        // odrcore streams the parts the edit did not touch out of the file it opened, and
        // truncates the destination first - so saving onto the open document empties it
        let output = URL(fileURLWithPath: outputPath)

        let staging = try stagingDirectory(for: output)
        defer { try? FileManager.default.removeItem(at: staging) }

        let temporary = stagedFile(in: staging, for: output)

        try document.save(to: temporary.path)

        try moveIntoPlace(from: temporary, to: output)
    }

    /// A directory on `output`'s own volume, because `replaceItemAt` cannot swap across one.
    /// The caller has to delete it.
    private func stagingDirectory(for output: URL) throws -> URL {
        // a target the user has only just named does not exist yet, so its directory
        // names the volume instead
        let reference =
            FileManager.default.fileExists(atPath: output.path)
            ? output : output.deletingLastPathComponent()

        return try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: reference,
            create: true)
    }

    /// Keeps `output`'s extension, which is what odrcore detects the file type from.
    private func stagedFile(in directory: URL, for output: URL) -> URL {
        let staged = directory.appendingPathComponent("odr-save-\(UUID().uuidString)")

        guard !output.pathExtension.isEmpty else { return staged }

        return staged.appendingPathExtension(output.pathExtension)
    }

    private func moveIntoPlace(from temporary: URL, to output: URL) throws {
        // replaceItemAt needs something to replace, and a newly named target has nothing
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: output)
        }
    }

    /// Whether odrcore is serving this URL, rather than it being somewhere a
    /// link in the document leads.
    @objc static func isServedURL(_ url: URL) -> Bool {
        let port = PageServer.shared.port

        return port != 0 && url.scheme == "http" && url.host == "127.0.0.1"
            && url.port.map(UInt32.init) == port
    }
}
