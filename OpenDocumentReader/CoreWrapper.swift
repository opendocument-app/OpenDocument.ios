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

    /// Serve the translation under a fresh URL to bypass WebKit caches; nil on failure.
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

/// Use one tab per spreadsheet sheet; prefer the combined view for other documents.
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

    /// Whether `save` has something to apply an edit to. Only a file that said
    /// it takes one is kept, so having it *is* the answer.
    @objc var isEditable: Bool { lock.withLock { document != nil || textFile != nil } }

    /// Whether the file is a pdf that takes marks.
    @objc var isAnnotatable: Bool { lock.withLock { pdfFile != nil } }

    /// Whether the file is plain text, which takes typing but no formatting.
    @objc var isPlainText: Bool { lock.withLock { textFile != nil } }
    /// The page size the document is laid out for, in points; zero where it has none.
    @objc private(set) var pageSize: CGSize = .zero
    /// Whether the file is a pdf the print system can read as it is.
    @objc private(set) var isPrintablePdf = false

    private var document: OdrCoreObjC.Document?
    private var textFile: TextFile?
    private var pdfFile: PdfFile?
    private let lock = NSRecursiveLock()

    /// The largest sheet region translated, as on OpenDocument.droid.
    private static let spreadsheetLimit = TableDimensions(rows: 100_000, columns: 500)

    /// Bounds the rows by the sheet's width: the wider, the fewer it keeps.
    private static let spreadsheetCellLimit: UInt64 = 500_000

    /// The name the web view's message handler is added under.
    @objc static let pageMessageName = "odr"

    /// The function the page calls with each message, as a path from `window`.
    private static let hostMessageHandler = "webkit.messageHandlers.\(pageMessageName).postMessage"

    @objc func translate(
        _ inputPath: String,
        into outputPath: String,
        with password: String?,
        editable: Bool,
        scope: HtmlEditingScope
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        pageNames = []
        pageURLs = []
        document = nil
        textFile = nil
        pdfFile = nil
        isArchive = false
        pageSize = .zero
        isPrintablePdf = false

        let fileTypes = (try? DecodedFile.listFileTypes(path: inputPath)) ?? []
        guard !fileTypes.isEmpty else {
            throw coreWrapperError(.unsupportedFileType, "odrcore does not recognise this file type")
        }

        var file = try DecodedFile.decode(path: inputPath)
        let encrypted = file.isPasswordEncrypted
        if encrypted {
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

        // Keep rendering settings consistent with OpenDocument.droid.
        let config = HtmlConfig()
        config.editable = editable
        // how far an edit may reach: inside one paragraph, or across the
        // document with formatting
        config.editingScope = scope
        // resource paths are resolved relative to an output directory, and in
        // server mode there is none — odrcore rejects the combination
        config.relativeResourcePaths = false
        // Keep page margins and enable paged layout.
        config.textDocumentMargin = true
        // Follow system appearance; PDFs remain light.
        config.colorScheme = .system
        // served with the pages rather than inlined as base64
        config.embedImages = false
        // odrcore's own css and js go into the page: there is no output
        // directory to put them beside
        config.embedShippedResources = true
        // the page measures the view and fits itself to it: a web view does not
        // fit a page to the screen the way a browser does
        config.viewportMode = .fitWidthByView
        // stated rather than inherited: a sheet past the limit is cut off silently
        config.spreadsheetLimit = Self.spreadsheetLimit
        config.spreadsheetCellLimit = Self.spreadsheetCellLimit
        config.spreadsheetLimitByContent = true
        // the page sends every `odr.on*` callback here as one JSON string, so
        // the app needs no script of its own in the page
        config.hostMessageHandler = Self.hostMessageHandler
        // a tap opens the cell editor: the page would ask the pointer, and a
        // web view answers it as a mouse
        config.sheetEditOnClick = true
        // an armed marker marks each selection as it is made: a tap elsewhere
        // would lose it
        config.pdfAnnotationMarkOnSelection = true

        let documentType: DocumentType
        let openedDocument: OdrCoreObjC.Document?
        var openedTextFile: TextFile?
        var openedPdfFile: PdfFile?
        var openedPageSize: CGSize?
        let service: HtmlService

        if let document = try Self.document(of: file) {
            documentType = document.documentType
            // the document's own answer: a format odrcore renders but cannot write
            // back would otherwise offer Edit and fail at the save
            openedDocument = document.isEditable && document.isSavable ? document : nil
            openedPageSize = Self.pageSize(of: document)
            service = try HtmlTranslator.translate(document: document, config: config)
        } else {
            // `.unknown` keeps the single view each of these has -
            // `.spreadsheet` would ask for a tab per sheet
            documentType = .unknown
            openedDocument = nil

            if file.isTextFile, let text = try? file.asTextFile(), text.isSavable {
                openedTextFile = text
            }
            if file.isPdfFile, file.capabilities.annotate, let pdf = try? file.asPdfFile(),
                pdf.isAnnotatable
            {
                openedPdfFile = pdf
            }

            service = try HtmlTranslator.translate(file: file, config: config)
        }

        let views = selectViews(service.views, documentType)
        guard !views.isEmpty else {
            throw coreWrapperError(.unknown, "odrcore produced no displayable page")
        }

        guard let base = PageServer.shared.connect(service) else {
            throw coreWrapperError(.unknown, "could not serve the translated document")
        }

        // only once nothing can throw any more: a save must not be handed a
        // file whose pages were never served
        self.document = openedDocument
        self.textFile = openedTextFile
        self.pdfFile = openedPdfFile
        pageSize = openedPageSize ?? .zero
        isPrintablePdf = file.isPdfFile && !encrypted

        isArchive = file.isArchiveFile
        pageNames = views.map(\.name)
        pageURLs = views.map { base.appendingPathComponent($0.path) }
    }

    /// The document behind the file. A csv is a one-sheet spreadsheet, but an
    /// encoding odrcore cannot decode leaves it only the text view.
    private static func document(of file: DecodedFile) throws -> OdrCoreObjC.Document? {
        if file.isDocumentFile {
            return try file.asDocumentFile().document()
        }
        if file.isCsvFile {
            return try? file.asCsvFile().document()
        }
        return nil
    }

    /// The first page's: a presentation has one size, and a drawing seldom more.
    private static func pageSize(of document: OdrCoreObjC.Document) -> CGSize? {
        guard let root = try? document.rootElement() else {
            return nil
        }
        let layout: PageLayout?
        switch document.documentType {
        case .text: layout = (root as? TextRoot)?.pageLayout
        case .presentation: layout = (root.firstChild as? Slide)?.pageLayout
        case .drawing: layout = (root.firstChild as? OdrCoreObjC.Page)?.pageLayout
        default: layout = nil
        }
        guard let layout else {
            return nil
        }
        return PrintPaper.size(width: layout.width, height: layout.height)
    }

    /// The script the page hands its edits back through: the editor's log for
    /// a document or a text file, the marks for a pdf.
    @objc var editPayloadScript: String {
        isAnnotatable ? "odr.annotation.getAnnotations()" : "odr.editing.getOperations()"
    }

    /// Writes the file with `payload` applied - the page's operations, or its
    /// marks for a pdf.
    @objc func save(_ payload: String, into outputPath: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // every kind of file is written beside the output and swapped in, so a
        // failed save leaves the open file as it was
        let output = URL(fileURLWithPath: outputPath)

        let staging = try stagingDirectory(for: output)
        defer { try? FileManager.default.removeItem(at: staging) }

        let temporary = stagedFile(in: staging, for: output)

        if let document {
            if Self.holdsOperations(payload) {
                try document.edit(operations: payload)
            }
            try document.save(to: temporary.path)
        } else if let textFile {
            try textFile.edit(operations: payload)
            try textFile.save(to: temporary.path)
        } else if let pdfFile {
            try pdfFile.annotate(payload).write(to: temporary)
        } else {
            throw coreWrapperError(.unknown, "no editable file has been translated yet")
        }

        try moveIntoPlace(from: temporary, to: output)
    }

    /// Whether the envelope carries any operation: an empty one is a save of
    /// the file as it is.
    private static func holdsOperations(_ payload: String) -> Bool {
        guard let data = payload.data(using: .utf8),
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ops = envelope["ops"] as? [Any]
        else {
            return true
        }

        return !ops.isEmpty
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
            && url.port == Int(port)
    }
}
