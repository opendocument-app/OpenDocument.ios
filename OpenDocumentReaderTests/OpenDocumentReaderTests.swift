//
//  OpenDocumentReaderTests.swift
//  OpenDocumentReaderTests
//
//  Created by Thomas Taschauer on 08.11.20.
//  Copyright © 2020 Thomas Taschauer. All rights reserved.
//

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

        XCTAssertFalse(wrapper.pagePaths.isEmpty)
        XCTAssertEqual(wrapper.pagePaths.count, wrapper.pageNames.count)
        for path in wrapper.pagePaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "missing page at \(path)")
        }
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

    /// Views that are not shown must not be rendered either.
    func testDiscardedPagesAreNotWrittenOut() throws {
        let (wrapper, cache, _) = makeWrapper()
        let output = NSTemporaryDirectory() + "presentation-output"
        try? FileManager.default.removeItem(atPath: output)
        let url = try copyFixture(ofType: "odp")

        try wrapper.translate(url.path, cache: cache, into: output, with: nil, editable: false)

        let written = try FileManager.default.contentsOfDirectory(atPath: output)
            .filter { $0.hasSuffix(".html") }
        XCTAssertEqual(written, ["document.html"])
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
