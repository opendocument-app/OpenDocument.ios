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
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false)

        saveURL = documentsURL.appendingPathComponent("test.odt")

        if FileManager.default.fileExists(atPath: saveURL.path) {
            try FileManager.default.removeItem(at: saveURL)
        }

        let bundlePath = try XCTUnwrap(
            Bundle(for: type(of: self)).path(forResource: "test", ofType: "odt"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: saveURL)
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
