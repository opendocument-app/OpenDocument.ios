//
//  CoreWrapper.swift
//  OpenDocument Reader
//
//  Replaces the ObjC++ CoreWrapper that talked to odrcore's C++ API directly.
//  odrcore now arrives as the `OdrCore` Swift package, so the app links a
//  prebuilt xcframework instead of building the library through conan.
//

import Foundation
import OdrCore
import OdrCoreObjC

let CoreWrapperErrorDomain = "app.opendocument.CoreWrapperErrorDomain"

@objc enum CoreWrapperError: Int {
    /// odrcore threw something we have no specific handling for.
    case unknown = 1
    /// The document is encrypted and the supplied password did not open it.
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

    /// Bound port, or 0 when there is no server.
    var port: UInt32 { lock.withLock { handle?.port ?? 0 } }

    /// Connects `service` under a prefix nothing has been served under before,
    /// and returns the base URL for it. Nil if the socket could not be opened.
    ///
    /// A fresh prefix every time because the web view caches by URL:
    /// re-translating after a password or an edit has to end up at an address
    /// it has not seen.
    func connect(_ service: HtmlService) -> (prefix: String, base: URL)? {
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

        return (prefix, handle.url(prefix: prefix))
    }
}

/// The view odrcore names "document" holds the whole file in one page: every
/// slide of a presentation, every page of a PDF, the entire text document.
private func isCombinedView(_ view: HtmlView) -> Bool { view.name == "document" }

/// Picks the views to show as pages, the same way OpenDocument.droid does.
///
/// Spreadsheets get one tab per sheet, because scrolling through every sheet of
/// a workbook in one page is not how anyone reads a spreadsheet. Everything else
/// gets the combined view and nothing else — a presentation would otherwise show
/// its slides twice, and a PDF would list one tab per page next to the tab that
/// already has them all.
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

        guard file.isDocumentFile else {
            throw coreWrapperError(.unsupportedFileType, "not a document file")
        }

        let documentFile = try file.asDocumentFile()
        let documentType = documentFile.documentType
        let document = try documentFile.document()
        self.document = document

        let config = HtmlConfig()
        config.editable = editable
        // resource paths are resolved relative to an output directory, and in
        // server mode there is none — odrcore rejects the combination
        config.relativeResourcePaths = false

        let service = try HtmlTranslator.translate(
            document: document, cachePath: cachePath, config: config)

        // the views are picked before they are rendered: bringing all of them
        // offline first would write out every slide of a presentation only to
        // throw the files away again
        let views = selectViews(service.views, documentType)
        guard !views.isEmpty else {
            throw coreWrapperError(.unknown, "odrcore produced no displayable page")
        }

        guard let connected = PageServer.shared.connect(service) else {
            throw coreWrapperError(.unknown, "could not serve the translated document")
        }

        pageNames = views.map(\.name)
        pageURLs = views.map { connected.base.appendingPathComponent($0.path) }
    }

    @objc func backTranslate(_ diff: String, into outputPath: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let document else {
            throw coreWrapperError(.unknown, "no document has been translated yet")
        }

        try HtmlTranslator.edit(document: document, diff: diff)
        try document.save(to: outputPath)
    }

    /// Whether this URL is one odrcore is serving, rather than somewhere a link
    /// in the document leads.
    @objc static func isServedURL(_ url: URL) -> Bool {
        let port = PageServer.shared.port

        return port != 0 && url.scheme == "http" && url.host == "127.0.0.1"
            && url.port.map(UInt32.init) == port
    }
}
