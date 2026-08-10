import Foundation
import OdrCore
import OdrCoreObjC

let CoreWrapperErrorDomain = "app.opendocument.CoreWrapperErrorDomain"

@objc enum CoreWrapperError: Int {
    case unknown = 1
    case wrongPassword = 2
    /// Not a document odrcore can translate. PDFs land here on purpose.
    case unsupportedFileType = 3
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

/// A csv is a *text* file to odrcore that also loads as a spreadsheet, so it
/// answers `isDocumentFile` with false and `asDocumentFile()` fails on it.
private func isCsv(_ file: DecodedFile) -> Bool { file.fileType == .commaSeparatedValues }

@objc final class CoreWrapper: NSObject {
    @objc private(set) var pageNames: [String] = []
    @objc private(set) var pageURLs: [URL] = []

    /// Whether `backTranslate` has a document to apply an edit to. Only a
    /// document that said it takes one is kept, so having it *is* the answer.
    @objc var isEditable: Bool { lock.withLock { document != nil } }

    private var document: OdrCoreObjC.Document?
    private let lock = NSRecursiveLock()

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

        let fileTypes = (try? DecodedFile.listFileTypes(path: inputPath)) ?? []
        guard !fileTypes.isEmpty else {
            throw coreWrapperError(.unsupportedFileType, "odrcore does not recognise this file type")
        }
        // PDFs are handed to WKWebView instead, which renders them natively
        guard !fileTypes.contains(NSNumber(value: FileType.portableDocumentFormat.rawValue)) else {
            throw coreWrapperError(
                .unsupportedFileType, "PDF is rendered by the web view, not by odrcore")
        }

        var file = try DecodedFile.decode(path: inputPath)
        if file.isPasswordEncrypted {
            do {
                file = try file.decrypt(withPassword: password ?? "")
            } catch let error as NSError
                where error.code == ODRError.wrongPassword.rawValue
            {
                throw coreWrapperError(.wrongPassword, "wrong password")
            }
        }

        guard file.isDocumentFile || isCsv(file) else {
            throw coreWrapperError(.unsupportedFileType, "not a document file")
        }

        let config = HtmlConfig()
        config.editable = editable
        // resource paths are resolved relative to an output directory, and in
        // server mode there is none — odrcore rejects the combination
        config.relativeResourcePaths = false
        // the side margins of a printed page, which is what it was written to look like
        config.textDocumentMargin = true

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
            // not `.spreadsheet`, though a csv is one: that asks for a tab per
            // sheet, and a csv's single sheet is called "csv"
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

        // Never straight onto `outputPath`, which is the document we are editing: odrcore
        // rewrites only the parts the edit touched and streams the rest - styles, images,
        // the mimetype entry - out of the file it opened, and it truncates the destination
        // before that read happens. Writing in place therefore reads back what it has just
        // emptied and leaves an archive of blank parts where the document was.
        let output = URL(fileURLWithPath: outputPath)

        let staging = try stagingDirectory(for: output)
        defer { try? FileManager.default.removeItem(at: staging) }

        let temporary = stagedFile(in: staging, for: output)

        try document.save(to: temporary.path)

        try moveIntoPlace(from: temporary, to: output)
    }

    /// A directory to save into before taking `output`'s place, on `output`'s own volume.
    ///
    /// Not `NSTemporaryDirectory()`: that lives in the app container, and ``moveIntoPlace``
    /// swaps with `replaceItemAt`, which cannot reach across volumes - a document opened out
    /// of iCloud Drive or another Files provider is rarely on the same one.
    ///
    /// The caller owns what this returns and has to delete it.
    private func stagingDirectory(for output: URL) throws -> URL {
        // an existing file is what names the volume; a save target the user has only just
        // named does not exist yet, so its directory answers for it
        let reference =
            FileManager.default.fileExists(atPath: output.path)
            ? output : output.deletingLastPathComponent()

        return try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: reference,
            create: true)
    }

    /// Keeps `output`'s extension, so odrcore's own file type detection reads the staged copy
    /// the same way it reads the document.
    private func stagedFile(in directory: URL, for output: URL) -> URL {
        let staged = directory.appendingPathComponent("odr-save-\(UUID().uuidString)")

        guard !output.pathExtension.isEmpty else { return staged }

        return staged.appendingPathExtension(output.pathExtension)
    }

    /// Replaces `output` with the file at `temporary`.
    ///
    /// `replaceItemAt` only where there is something to replace - it needs an existing item,
    /// and a save target the user has just named may not exist yet.
    private func moveIntoPlace(from temporary: URL, to output: URL) throws {
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
