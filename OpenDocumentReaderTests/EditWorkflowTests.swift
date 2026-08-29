import WebKit
import XCTest

@testable import OpenDocumentReader

/// The whole round trip, driven through the real view controller rather than
/// through ``CoreWrapper`` alone: the bar is half of what makes editing work,
/// and it is the half that broke.
class EditWorkflowTests: XCTestCase {
    private var documentURL: URL!
    private var window: UIWindow!
    private var controller: DocumentViewController!
    private var document: Document!

    private static let editedText = "Edited by the test"

    override func setUpWithError() throws {
        documentURL = try copyFixture(ofType: "odt")
        try present(documentURL)
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        document = nil
    }

    /// Out of the read-only test bundle, and away from the temporary directory
    /// translating uses for its cache and output.
    private func copyFixture(ofType pathExtension: String) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        let url = documentsURL.appendingPathComponent("edit-workflow." + pathExtension)
        try? FileManager.default.removeItem(at: url)

        let bundlePath = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: "test", ofType: pathExtension))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: url)

        return url
    }

    /// On a key window, because the controller hands the web view to the
    /// document as it appears and the page has to be laid out to be tapped.
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

    // MARK: - the bar

    func testAnEditableDocumentOffersThePencil() throws {
        openDocument()

        XCTAssertTrue(barContains(controller.editButton))
        XCTAssertEqual(controller.editButton.image, UIImage(systemName: "pencil"))
    }

    /// What used to happen instead: the button left the bar, and saving was only
    /// reachable through the menu.
    func testThePencilBecomesASaveButtonWhileEditing() throws {
        openDocument()

        controller.editOrSave(controller.editButton)
        waitForEditablePage()

        XCTAssertTrue(document.edit)
        XCTAssertTrue(barContains(controller.editButton))
        XCTAssertEqual(controller.editButton.image, UIImage(systemName: "square.and.arrow.down"))
    }

    /// A document nothing can be written back to keeps the room for itself.
    func testACsvOffersNoEditButton() throws {
        try present(try copyFixture(ofType: "csv"))
        openDocument()

        XCTAssertFalse(controller.document?.isEditable ?? true)
        XCTAssertFalse(barContains(controller.editButton))
    }

    // MARK: - the page

    /// The one thing edit mode is for. odrcore marks the text runs
    /// `contenteditable`, but a tap has to reach one for the caret to be set and
    /// the keyboard to unfold.
    func testTappingTheTextReachesTheEditableRun() throws {
        openDocument()

        controller.editOrSave(controller.editButton)
        waitForEditablePage()

        let tapped =
            evaluate(
                """
                (function () {
                    var run = document.querySelector('[contenteditable]');
                    // not getBoundingClientRect: the view applies a zoom to fit,
                    // which webkit leaves out of it but elementFromPoint expects
                    var box = odr.getViewportRect(run);
                    var hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);

                    return hit ? hit.tagName : 'none';
                })()
                """) as? String

        XCTAssertEqual(tapped, "X-S")
    }

    /// Programmatic focus is not what the user does, but it proves the run is
    /// editable and that only reaching it is the problem.
    func testAFocusedRunTakesTheEdit() throws {
        openDocument()

        controller.editOrSave(controller.editButton)
        waitForEditablePage()

        typeIntoTheFirstRun()

        XCTAssertEqual(evaluate("document.querySelector('[contenteditable]').innerText") as? String, Self.editedText)
    }

    // MARK: - the save

    func testSavingWritesTheEditToTheFile() throws {
        openDocument()

        controller.editOrSave(controller.editButton)
        waitForEditablePage()
        typeIntoTheFirstRun()

        let saved = expectation(description: "saved")
        controller.saveContent { success in
            XCTAssertTrue(success)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 60)

        XCTAssertTrue(try reopenedText().contains(Self.editedText))
    }

    /// The save button is the way out of the edit as well as the way to write
    /// it: a page left editable after a successful save has no button left to
    /// end it.
    func testSavingFromTheBarLeavesEditMode() throws {
        openDocument()

        controller.editOrSave(controller.editButton)
        waitForEditablePage()
        typeIntoTheFirstRun()

        controller.editOrSave(controller.editButton)
        waitForPage(where: "document.querySelectorAll('[contenteditable]').length === 0")

        XCTAssertFalse(document.edit)
        XCTAssertEqual(controller.editButton.image, UIImage(systemName: "pencil"))
        XCTAssertTrue(try reopenedText().contains(Self.editedText))
    }

    /// The way back to reading without saving, and the only one besides leaving
    /// the document altogether.
    func testDiscardingChangesLeavesEditModeAndTheFileAlone() throws {
        openDocument()

        controller.editOrSave(controller.editButton)
        waitForEditablePage()
        typeIntoTheFirstRun()

        controller.discardChanges()
        waitForPage(where: "document.querySelectorAll('x-s').length > 0")

        XCTAssertFalse(document.edit)
        XCTAssertEqual(controller.editButton.image, UIImage(systemName: "pencil"))
        XCTAssertFalse(try reopenedText().contains(Self.editedText))
    }

    // MARK: - helpers

    private func barContains(_ item: UIBarButtonItem) -> Bool {
        (controller.toolBar.items ?? []).contains { $0 === item }
    }

    private func openDocument() {
        let opened = expectation(description: "opened")
        document.open { success in
            XCTAssertTrue(success)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 60)

        waitForPage(where: "document.querySelectorAll('x-s').length > 0")
    }

    private func waitForEditablePage() {
        waitForPage(where: "document.querySelectorAll('[contenteditable]').length > 0")
    }

    /// The controller is its own navigation delegate — taking that away is what
    /// tells the tool bar what the page can do — so the test waits on the page
    /// itself rather than on `didFinish`.
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

    /// A change to the text node, which is what typing amounts to: odrcore's
    /// script watches for `characterData` and notes the run it belongs to.
    private func typeIntoTheFirstRun() {
        _ = evaluate(
            """
            (function () {
                var run = document.querySelector('[contenteditable]');
                run.focus();
                run.firstChild.data = '\(Self.editedText)';
            })()
            """)

        // the mutation is reported in a microtask, so the diff is only complete
        // on the next turn
        _ = XCTWaiter.wait(for: [expectation(description: "the observer to run")], timeout: 0.5)
    }

    /// Errors are swallowed: a page that is not there yet is what the polling
    /// above is waiting for.
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

    /// The file as it now stands on disk, translated afresh.
    private func reopenedText() throws -> String {
        let wrapper = CoreWrapper()
        let temporaryDirectory = NSTemporaryDirectory()

        try wrapper.translate(
            documentURL.path, cache: temporaryDirectory, into: temporaryDirectory, with: nil, editable: false)

        let url = try XCTUnwrap(wrapper.pageURLs.first)

        var html = ""
        let fetched = expectation(description: "fetched")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            html = String(decoding: data ?? Data(), as: UTF8.self)
            fetched.fulfill()
        }.resume()
        wait(for: [fetched], timeout: 30)

        return html
    }
}
