import WebKit
import XCTest

@testable import OpenDocumentReader

/// The app offers itself for a zip, because that is the type every ODF and
/// Office file conforms to. One that is only a zip has to open too: odrcore
/// lists what is inside it, and the listing's links have to lead somewhere.
class ArchiveDocumentTests: XCTestCase {
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
    private func copyFixture(ofType pathExtension: String = "zip") throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        let url = documentsURL.appendingPathComponent("test." + pathExtension)
        try? FileManager.default.removeItem(at: url)

        let bundlePath = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: "test", ofType: pathExtension))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: url)

        return url
    }

    /// One page, the listing, rather than the error a zip used to be.
    func testAZipTranslatesIntoItsListing() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        XCTAssertEqual(wrapper.pageNames, ["files"])
    }

    /// Nothing in a zip is editable, whatever the file inside it is.
    func testAZipIsNotEditable() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: true)

        XCTAssertFalse(wrapper.isEditable)
    }

    /// The listing names every file in the zip, and its links answer with them.
    func testTheListingOpensWhatIsInside() throws {
        let wrapper = CoreWrapper()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        let listingURL = try XCTUnwrap(wrapper.pageURLs.first)
        let (data, _) = try fetch(listingURL)
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))

        for name in ["notes.txt", "holiday/photo.jpg", "holiday/second.jpg"] {
            XCTAssertTrue(html.contains(name), html)
        }

        for href in hrefs(in: html) {
            let url = try XCTUnwrap(URL(string: href, relativeTo: listingURL)?.absoluteURL)
            let (entry, response) = try fetch(url)

            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, href)
            XCTAssertFalse(entry.isEmpty, href)
        }
    }

    /// End to end: the reader shows the listing, not the message it shows for a
    /// file it cannot open.
    func testAZipReachesTheReader() throws {
        try present(documentURL)

        let opened = expectation(description: "opened")
        document.open { _ in opened.fulfill() }
        wait(for: [opened], timeout: 60)

        waitForPage(where: "document.body.innerText.length > 0")

        let shown = try XCTUnwrap(evaluate("document.body.innerText") as? String)
        XCTAssertTrue(shown.contains("notes.txt"), shown)
        XCTAssertFalse(shown.contains(NSLocalizedString("toast_error_generic", comment: "")), shown)
    }

    /// odrcore has no iWork reader, so a `.pages` is a zip to it — but the
    /// system knows it as a document and draws it properly. It gets the first
    /// go, and the listing is only what the reader falls back to.
    func testADocumentTheSystemKnowsIsLeftToTheSystem() throws {
        try present(try copyFixture(ofType: "pages"))

        let opened = expectation(description: "opened")
        document.open { _ in opened.fulfill() }
        wait(for: [opened], timeout: 60)

        let shown = try XCTUnwrap(waitForURL { $0.isFileURL })

        XCTAssertEqual(shown.lastPathComponent, "test.pages")
        XCTAssertNil(controller.presentedViewController, "it said the file would not open")
    }

    /// And when the system turns out not to be able to draw it after all, the
    /// listing takes over rather than a message — an `.epub` is composite
    /// content to the system, which has no reader for it either.
    func testAnArchiveTheSystemCannotDrawFallsBackToTheListing() throws {
        try present(try copyFixture(ofType: "epub"))

        let opened = expectation(description: "opened")
        document.open { _ in opened.fulfill() }
        wait(for: [opened], timeout: 60)

        let shown = try XCTUnwrap(waitForURL { CoreWrapper.isServedURL($0) })

        XCTAssertEqual(shown.lastPathComponent, "files.html")
        XCTAssertNil(controller.presentedViewController, "it said the file would not open")
    }

    private func waitForURL(_ matches: (URL) -> Bool) -> URL? {
        let deadline = Date().addingTimeInterval(30)

        while Date() < deadline {
            if let url = controller.webview.url, matches(url) { return url }

            _ = XCTWaiter.wait(for: [expectation(description: "a turn of the run loop")], timeout: 0.1)
        }

        return controller.webview.url
    }

    /// odrcore writes the listing's links with `target="_blank"`, and a web view
    /// with nobody to answer that drops the tap on the floor.
    func testFollowingALinkOpensTheFileInTheSameWebView() throws {
        try present(documentURL)

        let opened = expectation(description: "opened")
        document.open { _ in opened.fulfill() }
        wait(for: [opened], timeout: 60)

        waitForPage(where: "document.body.innerText.length > 0")

        let listingURL = controller.webview.url
        evaluate("document.querySelector('.odr-files-name a').click()")

        waitForPage(where: "true")
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, controller.webview.url == listingURL {
            _ = XCTWaiter.wait(for: [expectation(description: "a turn of the run loop")], timeout: 0.1)
        }

        let reached = try XCTUnwrap(controller.webview.url)
        XCTAssertNotEqual(reached, listingURL)
        XCTAssertTrue(CoreWrapper.isServedURL(reached), reached.absoluteString)

        let settled = Date().addingTimeInterval(30)
        while Date() < settled, !controller.webview.canGoBack {
            _ = XCTWaiter.wait(for: [expectation(description: "a turn of the run loop")], timeout: 0.1)
        }

        XCTAssertTrue(controller.webview.canGoBack, "no way back to the listing")
    }

    // MARK: - helpers

    private func hrefs(in html: String) -> [String] {
        var found: [String] = []
        var rest = html[...]

        while let start = rest.range(of: "href=\"") {
            let tail = rest[start.upperBound...]
            guard let end = tail.firstIndex(of: "\"") else { break }

            let href = String(tail[..<end])
            // the download links carry the same targets, and a `data:` one is
            // not the server's to answer
            if !href.hasPrefix("data:"), !found.contains(href) {
                found.append(href)
            }
            rest = tail[end...]
        }

        return found
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
