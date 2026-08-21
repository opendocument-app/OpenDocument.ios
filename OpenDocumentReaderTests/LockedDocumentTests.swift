import WebKit
import XCTest

@testable import OpenDocumentReader

/// A legacy Word, Excel or PowerPoint file can say it is password protected,
/// and no password opens it: odrcore reads the flag but cannot decrypt any of
/// them. The reader has to say so rather than ask, and rather than hand the
/// file to the web view, which makes nothing of it either.
class LockedDocumentTests: XCTestCase {
    private let temporaryDirectory = NSTemporaryDirectory()
    private var documentURL: URL!
    private var window: UIWindow!
    private var controller: DocumentViewController!
    private var document: Document!

    override func setUpWithError() throws {
        documentURL = try copyFixture()
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        document = nil
    }

    /// Out of the read-only test bundle, and away from the temporary directory
    /// translating uses for its cache and output.
    private func copyFixture() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        let url = documentsURL.appendingPathComponent("locked.doc")
        try? FileManager.default.removeItem(at: url)

        let bundlePath = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: "test-encrypted", ofType: "doc"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: url)

        return url
    }

    /// Its own code, not `wrongPassword`: that one puts the prompt up, and the
    /// prompt would only come back.
    func testALockedLegacyFileReportsItsOwnError() throws {
        let wrapper = CoreWrapper()

        for password in [nil, "secret"] {
            XCTAssertThrowsError(
                try wrapper.translate(
                    documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: password,
                    editable: false)
            ) { error in
                XCTAssertEqual((error as NSError).code, CoreWrapperError.undecryptable.rawValue)
            }
        }
    }

    /// `.doc` is one of the formats the reader otherwise falls back to the web
    /// view for, so the message has to beat the fallback.
    func testALockedLegacyFileSaysWhyItDidNotOpen() throws {
        try present(documentURL)

        let opened = expectation(description: "opened")
        document.open { _ in opened.fulfill() }
        wait(for: [opened], timeout: 60)

        waitForPage(where: "document.body.innerText.length > 0")

        let shown = try XCTUnwrap(evaluate("document.body.innerText") as? String)
        XCTAssertTrue(
            shown.contains(NSLocalizedString("toast_error_password_protected", comment: "")), shown)
        XCTAssertFalse(controller.webview.url?.isFileURL ?? false, "the file was handed to the web view")
    }

    // MARK: - helpers

    private func present(_ url: URL) throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: DocumentViewController.self))
        controller = try XCTUnwrap(
            storyboard.instantiateViewController(withIdentifier: "TextDocumentViewController")
                as? DocumentViewController)

        document = Document(fileURL: url)
        controller.document = document

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.layoutIfNeeded()
    }

    private func waitForPage(
        where condition: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(60)

        while Date() < deadline {
            if evaluate(condition) as? Bool == true { return }

            _ = XCTWaiter.wait(for: [expectation(description: "a turn of the run loop")], timeout: 0.1)
        }

        XCTFail("timed out waiting for \(condition)", file: file, line: line)
    }

    @discardableResult
    private func evaluate(_ script: String) -> Any? {
        let done = expectation(description: "evaluated")
        var result: Any?

        controller.webview.evaluateJavaScript(script) { value, _ in
            result = value
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        return result
    }
}
