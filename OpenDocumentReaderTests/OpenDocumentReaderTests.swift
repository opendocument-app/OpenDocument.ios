//
//  OpenDocumentReaderTests.swift
//  OpenDocumentReaderTests
//
//  Created by Thomas Taschauer on 08.11.20.
//  Copyright © 2020 Thomas Taschauer. All rights reserved.
//

import WebKit
import XCTest

@testable import OpenDocumentReader

class OpenDocumentReaderTests: XCTestCase {
    private let temporaryDirectory = NSTemporaryDirectory()
    private var documentURL: URL!

    override func setUpWithError() throws {
        documentURL = try copyFixture(ofType: "odt")
    }

    /// Out of the read-only test bundle, and away from the temporary directory
    /// translating uses for its cache and output.
    private func copyFixture(ofType pathExtension: String) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false)

        let url = documentsURL.appendingPathComponent("test." + pathExtension)
        try? FileManager.default.removeItem(at: url)

        let bundlePath = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: "test", ofType: pathExtension))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: url)

        return url
    }

    func testTranslatesDocumentIntoPages() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: true)

        XCTAssertFalse(wrapper.pageURLs.isEmpty)
        XCTAssertEqual(wrapper.pageURLs.count, wrapper.pageNames.count)
    }

    /// A text document has nothing but its combined view.
    func testTextDocumentIsASinglePage() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["document"])
    }

    /// The one format that drops the combined view: a workbook is read a sheet
    /// at a time.
    func testSpreadsheetBecomesOnePagePerSheet() throws {
        let wrapper = CoreWrapper()
        let url = try copyFixture(ofType: "ods")

        try wrapper.translate(
            url.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["Alpha", "Beta", "Gamma"])
    }

    /// The combined view already holds every slide, so listing the slides next
    /// to it would show each of them twice.
    func testPresentationKeepsOnlyTheCombinedPage() throws {
        let wrapper = CoreWrapper()
        let url = try copyFixture(ofType: "odp")

        try wrapper.translate(
            url.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["document"])
    }

    /// A csv reaches odrcore at all only through the decoded file — it is a text
    /// file that also loads as a spreadsheet, so `isDocumentFile` says no and the
    /// guard used to reject it outright.
    func testCsvIsTranslated() throws {
        let wrapper = CoreWrapper()
        let url = try copyFixture(ofType: "csv")

        try wrapper.translate(
            url.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["document"])
    }

    /// And it has no document behind it, so the menu must not offer to edit one.
    func testCsvIsNotEditable() throws {
        let wrapper = CoreWrapper()
        let url = try copyFixture(ofType: "csv")

        try wrapper.translate(
            url.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: true)

        XCTAssertFalse(wrapper.isEditable)
    }

    /// The odt does, which is what keeps the check above from passing vacuously.
    func testATextDocumentIsEditable() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: true)

        XCTAssertTrue(wrapper.isEditable)
    }

    /// Nothing is rendered to disk up front any more, so the pages have to come
    /// back off the loopback server odrcore is serving them on.
    func testPagesAreServedOverLoopback() throws {
        let wrapper = CoreWrapper()
        let url = try copyFixture(ofType: "ods")

        try wrapper.translate(
            url.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        XCTAssertFalse(wrapper.pageURLs.isEmpty)

        for pageURL in wrapper.pageURLs {
            XCTAssertEqual(pageURL.scheme, "http")

            let (data, response) = try fetch(pageURL)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "\(pageURL)")
            XCTAssertTrue(
                String(decoding: data, as: UTF8.self).contains("<html"), "\(pageURL) served no html")
        }
    }

    /// The same URL would come back out of the web view's cache holding the
    /// pages the document had before the password or the edit.
    func testRetranslatingMovesThePagesToNewAddresses() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)
        let before = wrapper.pageURLs

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: true)

        XCTAssertNotEqual(before, wrapper.pageURLs)
    }

    /// A missing `NSAllowsLocalNetworking` shows up here and nowhere else: App
    /// Transport Security applies to the web view, not to the `URLSession`
    /// above.
    func testTheWebViewLoadsAServedPage() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        let url = try XCTUnwrap(wrapper.pageURLs.first)
        let recorder = NavigationRecorder(finished: expectation(description: "loaded \(url)"))
        let webview = WKWebView()
        webview.navigationDelegate = recorder

        webview.load(URLRequest(url: url))

        wait(for: [recorder.finished], timeout: 30)
        XCTAssertNil(recorder.error)
    }

    /// A failing page is treated as the document failing to render, so a link
    /// in the document that answers 404 must not take the document down too.
    func testOnlyTheServersOwnURLsCountAsPages() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        let page = try XCTUnwrap(wrapper.pageURLs.first)
        XCTAssertTrue(CoreWrapper.isServedURL(page))

        let port = try XCTUnwrap(page.port)

        for other in [
            "https://opendocument.app/missing.html",
            "http://opendocument.app/missing.html",
            "http://127.0.0.1:\(port + 1)/file/odr1/document.html",
            "http://127.0.0.1/file/odr1/document.html",
            "http://localhost:\(port)/file/odr1/document.html",
        ] {
            XCTAssertFalse(CoreWrapper.isServedURL(try XCTUnwrap(URL(string: other))), other)
        }
    }

    private func fetch(_ url: URL) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error> = .failure(URLError(.timedOut))
        let done = expectation(description: "GET \(url)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data, let response {
                result = .success((data, response))
            } else if let error {
                result = .failure(error)
            }

            done.fulfill()
        }.resume()

        wait(for: [done], timeout: 30)

        return try result.get()
    }

    func testBackTranslateWritesEditedDocument() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: true)

        let editedURL = URL(fileURLWithPath: temporaryDirectory)
            .appendingPathComponent("test-edited.odt")
        try? FileManager.default.removeItem(at: editedURL)

        let diff = """
            {"modifiedText":{"/child:3/child:0":"This is a simple test document to demonstrate the DocumentLoaderwwww example!"}}
            """

        try wrapper.backTranslate(diff, into: editedURL.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: editedURL.path))
    }

    /// backTranslate used to dereference an empty std::optional when nothing had
    /// been translated yet.
    func testBackTranslateWithoutTranslateFails() {
        let wrapper = CoreWrapper()

        let editedURL = URL(fileURLWithPath: temporaryDirectory)
            .appendingPathComponent("never-translated.odt")

        XCTAssertThrowsError(try wrapper.backTranslate("{}", into: editedURL.path)) { error in
            XCTAssertEqual((error as NSError).domain, CoreWrapperErrorDomain)
        }
    }

    func testUnsupportedFileTypeReportsTypedError() throws {
        let wrapper = CoreWrapper()

        let notADocument = URL(fileURLWithPath: temporaryDirectory)
            .appendingPathComponent("not-a-document.odt")
        try "definitely not an office document".write(to: notADocument, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try wrapper.translate(
                notADocument.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)
        ) { error in
            let error = error as NSError
            XCTAssertEqual(error.domain, CoreWrapperErrorDomain)
            XCTAssertEqual(error.code, CoreWrapperError.unsupportedFileType.rawValue)
        }
    }

    func testTranslatePerformance() throws {
        let wrapper = CoreWrapper()
        let path = documentURL.path
        let directory = temporaryDirectory

        measure {
            do {
                try wrapper.translate(path, cache: directory, into: directory, with: nil, editable: true)
            } catch {
                XCTFail("translate threw \(error)")
            }
        }
    }
}

/// Fulfills its expectation once, whichever way the navigation ends.
private class NavigationRecorder: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation
    private(set) var error: Error?
    private var isDone = false

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    private func complete(_ error: Error?) {
        guard !isDone else { return }

        isDone = true
        self.error = error
        finished.fulfill()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        complete(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(error)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        complete(error)
    }
}
