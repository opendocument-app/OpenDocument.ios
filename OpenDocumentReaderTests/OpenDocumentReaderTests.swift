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
    private var saveURL: URL!

    override func setUpWithError() throws {
        saveURL = try copyFixture(ofType: "odt")
    }

    /// Copies a bundled fixture next to the documents directory, because
    /// translating writes its cache and output beside the input.
    private func copyFixture(ofType pathExtension: String) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false)

        let url = documentsURL.appendingPathComponent("test." + pathExtension)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let bundlePath = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: "test", ofType: pathExtension))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: url)

        return url
    }

    private func makeWrapper() -> (wrapper: CoreWrapper, cache: String, output: String) {
        let temporaryDirectory = NSTemporaryDirectory()

        return (CoreWrapper(), temporaryDirectory, temporaryDirectory)
    }

    func testTranslatesDocumentIntoPages() throws {
        let (wrapper, cache, output) = makeWrapper()

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: true)

        XCTAssertFalse(wrapper.pageURLs.isEmpty)
        XCTAssertEqual(wrapper.pageURLs.count, wrapper.pageNames.count)
    }

    /// A text document has nothing but its combined view.
    func testTextDocumentIsASinglePage() throws {
        let (wrapper, cache, output) = makeWrapper()

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["document"])
    }

    /// Spreadsheets are the one format that drops the combined view: a tab per
    /// sheet is how a workbook is read.
    func testSpreadsheetBecomesOnePagePerSheet() throws {
        let (wrapper, cache, output) = makeWrapper()
        let url = try copyFixture(ofType: "ods")

        try wrapper.translate(url.path, cache: cache, into: output, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["Alpha", "Beta", "Gamma"])
    }

    /// The combined view of a presentation already holds every slide, so
    /// listing the slides next to it would show each of them twice.
    func testPresentationKeepsOnlyTheCombinedPage() throws {
        let (wrapper, cache, output) = makeWrapper()
        let url = try copyFixture(ofType: "odp")

        try wrapper.translate(url.path, cache: cache, into: output, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["document"])
    }

    /// Nothing is rendered up front any more, so the pages have to come back
    /// from the loopback server odrcore is serving them on.
    func testPagesAreServedOverLoopback() throws {
        let (wrapper, cache, output) = makeWrapper()
        let url = try copyFixture(ofType: "ods")

        try wrapper.translate(url.path, cache: cache, into: output, with: nil, editable: false)

        for pageURL in wrapper.pageURLs {
            XCTAssertEqual(pageURL.scheme, "http")

            let (data, response) = try fetch(pageURL)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "\(pageURL)")
            XCTAssertTrue(
                String(decoding: data, as: UTF8.self).contains("<html"), "\(pageURL) served no html")
        }
    }

    /// Translating again has to produce addresses the web view has not cached
    /// yet - the same URL would come back out of its cache with the pages the
    /// document had before the password or the edit.
    func testRetranslatingMovesThePagesToNewAddresses() throws {
        let (wrapper, cache, output) = makeWrapper()

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: false)
        let before = wrapper.pageURLs

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: true)

        XCTAssertNotEqual(before, wrapper.pageURLs)
    }

    /// The web view is the actual consumer of those URLs, and the one App
    /// Transport Security applies to. A missing `NSAllowsLocalNetworking` would
    /// show up here and nowhere else - `URLSession` above would still be happy.
    func testTheWebViewLoadsAServedPage() throws {
        let (wrapper, cache, output) = makeWrapper()

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: false)

        let url = try XCTUnwrap(wrapper.pageURLs.first)
        let recorder = NavigationRecorder(finished: expectation(description: "loaded \(url)"))
        let webview = WKWebView()
        webview.navigationDelegate = recorder

        webview.load(URLRequest(url: url))

        wait(for: [recorder.finished], timeout: 30)
        XCTAssertNil(recorder.error)
    }

    /// A failing page is treated as the document failing to render, so what
    /// counts as one of our pages has to be narrow: a link in the document that
    /// answers 404 must not take the document down with it.
    func testOnlyTheServersOwnURLsCountAsPages() throws {
        let (wrapper, cache, output) = makeWrapper()

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: false)

        let page = try XCTUnwrap(wrapper.pageURLs.first)
        XCTAssertTrue(CoreWrapper.isServedURL(page))

        // the port is whichever one was free, so the near misses are spelled
        // relative to the one we actually got rather than a hardcoded number
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
        let (wrapper, cache, output) = makeWrapper()

        try wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: true)

        let editedURL = URL(fileURLWithPath: NSTemporaryDirectory())
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
        let (wrapper, _, _) = makeWrapper()

        let editedURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("never-translated.odt")

        XCTAssertThrowsError(try wrapper.backTranslate("{}", into: editedURL.path)) { error in
            XCTAssertEqual((error as NSError).domain, CoreWrapperErrorDomain)
        }
    }

    func testUnsupportedFileTypeReportsTypedError() throws {
        let (wrapper, cache, output) = makeWrapper()

        let notADocument = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-document.odt")
        try "definitely not an office document".write(to: notADocument, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try wrapper.translate(notADocument.path, cache: cache, into: output, with: nil, editable: false)
        ) { error in
            let error = error as NSError
            XCTAssertEqual(error.domain, CoreWrapperErrorDomain)
            XCTAssertEqual(error.code, CoreWrapperError.unsupportedFileType.rawValue)
        }
    }

    func testTranslatePerformance() throws {
        let (wrapper, cache, output) = makeWrapper()

        measure {
            try? wrapper.translate(saveURL.path, cache: cache, into: output, with: nil, editable: true)
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
