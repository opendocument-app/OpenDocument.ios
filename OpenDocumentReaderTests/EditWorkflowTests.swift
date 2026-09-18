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

    /// The website's two controls: the pen, drawn selected while the mode is on,
    /// and the disc beside it, there only while editing and live only once the
    /// page holds a change.
    func testThePenStaysAndTheSaveButtonJoinsItWhileEditing() throws {
        openDocument()

        XCTAssertFalse(barContains(controller.saveButton))

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()

        XCTAssertTrue(document.edit)
        XCTAssertTrue(barContains(controller.editButton))
        XCTAssertEqual(controller.editButton.image, UIImage(systemName: "pencil"))
        XCTAssertTrue(controller.editButton.isSelected)
        XCTAssertTrue(barContains(controller.saveButton))
        XCTAssertFalse(controller.saveButton.isEnabled)

        typeIntoTheFirstRun()
        waitUntil { self.controller.saveButton.isEnabled }
    }

    /// With nothing to lose the pen only turns the mode off, and the page stays.
    func testThePenLeavesAnUnchangedEditAtOnce() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()

        controller.toggleEdit(controller.editButton)
        waitForPage(where: "document.querySelectorAll('[contenteditable]').length === 0")

        XCTAssertFalse(document.edit)
        XCTAssertFalse(controller.editButton.isSelected)
        XCTAssertFalse(barContains(controller.saveButton))
        XCTAssertNil(controller.editToolBar.layout)
    }

    /// A document nothing can be written back to keeps the room for itself.
    func testACsvOffersNoEditButton() throws {
        documentURL = try copyFixture(ofType: "csv")
        try present(documentURL)
        openDocument(where: "typeof odr === 'object'")

        XCTAssertFalse(controller.document?.isEditable ?? true)
        XCTAssertFalse(barContains(controller.editButton))
    }

    // MARK: - the page

    /// The one thing edit mode is for. odrcore makes the flow `contenteditable`,
    /// but a tap has to reach a run for the caret to be set and the keyboard to
    /// unfold.
    func testTappingTheTextReachesTheEditableRun() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()

        let tapped =
            evaluate(
                """
                (function () {
                    var run = document.querySelector('x-s[data-odr-id]');
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

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()

        typeIntoTheFirstRun()

        let text = evaluate("document.querySelector('x-s[data-odr-id]').textContent") as? String ?? ""
        XCTAssertTrue(text.contains(Self.editedText), text)
    }

    // MARK: - the tools

    /// The row under the bar: formatting for a text document, once the page
    /// says it is editable, and gone again with the edit.
    func testATextDocumentShowsTheFormattingToolsWhileEditing() throws {
        openDocument()

        XCTAssertNil(controller.editToolBar.layout)

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()
        waitForTools()

        XCTAssertEqual(controller.editToolBar.layout, .text)
        XCTAssertTrue(controller.editToolBar.shows(.bold))
        XCTAssertTrue(controller.editToolBar.shows(.undo))

        controller.discardChanges()
        waitForPage(where: "document.querySelectorAll('x-s').length > 0")

        XCTAssertNil(controller.editToolBar.layout)
    }

    /// The cells are the editor, so a spreadsheet gets only the way back.
    func testASpreadsheetShowsOnlyUndoAndRedo() throws {
        documentURL = try copyFixture(ofType: "ods")
        try present(documentURL)
        openDocument(where: "document.querySelectorAll('td').length > 0")

        controller.toggleEdit(controller.editButton)
        waitForTools()

        XCTAssertEqual(controller.editToolBar.layout, .plain)
        XCTAssertFalse(controller.editToolBar.shows(.bold))
        XCTAssertTrue(controller.editToolBar.shows(.undo))
    }

    /// A style the caret sits in is shown pressed, the way the page reports it.
    func testTheSelectionStyleReachesTheButtons() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()
        waitForTools()

        _ = evaluate("odr.onSelectionChange({ bold: true, italic: false })")
        waitUntil { self.controller.editToolBar.isPressed(.bold) }

        XCTAssertFalse(controller.editToolBar.isPressed(.italic))
    }

    /// As on the website: the colour bars and the size follow the selection,
    /// and the highlight shows pressed where the selection has one.
    func testTheSelectionColorsAndSizeReachTheTools() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()
        waitForTools()

        XCTAssertNil(controller.editToolBar.fontSizeTitle)

        _ = evaluate("odr.onSelectionChange({ color: '#e53935', highlight: '#c5e1a5', size: '12pt' })")
        waitUntil { self.controller.editToolBar.isPressed(.highlight) }

        XCTAssertEqual(controller.editToolBar.color(of: .textColor)?.hexString, "#e53935")
        XCTAssertEqual(controller.editToolBar.color(of: .highlight)?.hexString, "#c5e1a5")
        XCTAssertEqual(controller.editToolBar.fontSizeTitle, "12 pt")
    }

    /// The highlight button turns a highlight on in its colour, and off again.
    func testTheHighlightButtonTogglesTheHighlight() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()
        waitForTools()
        selectTheFirstRun()

        controller.editToolBar.onTap?(.highlight)
        waitForPage(where: "document.querySelector('x-s[data-odr-id]').style.backgroundColor !== ''")

        _ = evaluate("odr.onSelectionChange({ highlight: '#fff59d' })")
        waitUntil { self.controller.editToolBar.isPressed(.highlight) }
        selectTheFirstRun()

        controller.editToolBar.onTap?(.highlight)
        waitForPage(where: "document.querySelector('x-s[data-odr-id]').style.backgroundColor === ''")
    }

    // MARK: - a pdf

    /// The pencil is a highlighter on a pdf, and the edit is a set of marks.
    func testAPdfOffersMarksAndSavesThem() throws {
        documentURL = try copyFixture(ofType: "pdf")
        try present(documentURL)
        openDocument(where: "document.querySelectorAll('[data-odr-space]').length > 0")

        XCTAssertTrue(document.isAnnotatable)
        XCTAssertTrue(barContains(controller.editButton))
        XCTAssertEqual(controller.editButton.image, UIImage(systemName: "highlighter"))

        let sizeBefore = try fileSize()

        controller.toggleEdit(controller.editButton)
        waitForPage(where: "document.querySelectorAll('[data-odr-space]').length > 0")
        waitForTools()

        XCTAssertEqual(controller.editToolBar.layout, .pdf)
        XCTAssertTrue(controller.editToolBar.shows(.markHighlight))
        XCTAssertFalse(controller.editToolBar.shows(.redo))

        // each marker has a colour of its own, as on the website
        XCTAssertEqual(controller.editToolBar.color(of: .markHighlight)?.hexString, "#ffe633")
        XCTAssertEqual(controller.editToolBar.color(of: .markDraw)?.hexString, "#1e88e5")

        let marks =
            evaluate(
                """
                (function () {
                    var page = document.querySelector('[data-odr-space]');
                    var range = document.createRange();
                    range.selectNodeContents(page);
                    var selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(range);
                    odr.annotation.setTool('highlight');
                    odr.annotation.mark();
                    return odr.annotation.list().length;
                })()
                """) as? Int ?? 0
        XCTAssertGreaterThan(marks, 0)

        let saved = expectation(description: "saved")
        controller.saveContent { success in
            XCTAssertTrue(success)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 60)

        // an incremental update: the marks are written after the file as it was
        XCTAssertGreaterThan(try fileSize(), sizeBefore)
        XCTAssertNoThrow(try reopenedText())
    }

    // MARK: - the save

    func testSavingWritesTheEditToTheFile() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
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

    /// As on the website, a save writes the edit and stays in it: the file is
    /// rendered again, and the new page is back in the mode with a clean log.
    func testSavingStaysInEditMode() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
        waitForEditablePage()
        typeIntoTheFirstRun()

        let saved = expectation(description: "saved")
        controller.saveAndStay { success in
            XCTAssertTrue(success)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 60)

        waitForPage(
            where:
                "document.querySelectorAll('[contenteditable]').length > 0 && document.body.textContent.indexOf('\(Self.editedText)') >= 0"
        )

        XCTAssertTrue(document.edit)
        XCTAssertTrue(controller.editButton.isSelected)
        XCTAssertTrue(barContains(controller.saveButton))
        XCTAssertTrue(try reopenedText().contains(Self.editedText))
    }

    /// A marker pressed with text selected marks it once and leaves no tool
    /// armed, the website's `markOnce`.
    func testAMarkerMarksASelectionOnceAndArmsNothing() throws {
        documentURL = try copyFixture(ofType: "pdf")
        try present(documentURL)
        openDocument(where: "document.querySelectorAll('[data-odr-space]').length > 0")

        controller.toggleEdit(controller.editButton)
        waitForTools()

        _ = evaluate(
            """
            (function () {
                var range = document.createRange();
                range.selectNodeContents(document.querySelector('[data-odr-space]'));
                var selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
            })()
            """)

        controller.editToolBar.onTap?(.markUnderline)
        waitForPage(where: "odr.annotation.list().length > 0")

        XCTAssertEqual(evaluate("odr.annotation.getTool() === null") as? Bool, true)
        XCTAssertFalse(controller.editToolBar.isPressed(.markUnderline))
    }

    /// The way back to reading without saving, and the only one besides leaving
    /// the document altogether.
    func testDiscardingChangesLeavesEditModeAndTheFileAlone() throws {
        openDocument()

        controller.toggleEdit(controller.editButton)
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

    private func openDocument(where condition: String = "document.querySelectorAll('x-s').length > 0") {
        let opened = expectation(description: "opened")
        document.open { success in
            XCTAssertTrue(success)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 60)

        waitForPage(where: condition)
    }

    /// The tools appear once the editable page has answered what it is.
    private func waitForTools(file: StaticString = #filePath, line: UInt = #line) {
        waitUntil(file: file, line: line) { self.controller.editToolBar.layout != nil }
    }

    /// A message from the page lands on a later turn of the run loop.
    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(60)

        while Date() < deadline {
            if condition() { return }

            _ = XCTWaiter.wait(for: [expectation(description: "a turn of the run loop")], timeout: 0.1)
        }

        XCTFail("timed out waiting for the controller", file: file, line: line)
    }

    private func fileSize() throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: documentURL.path)

        return attributes[.size] as? Int ?? 0
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

    private func selectTheFirstRun() {
        _ = evaluate(
            """
            (function () {
                var run = document.querySelector('x-s[data-odr-id]');
                var range = document.createRange();
                range.selectNodeContents(run);
                var selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
            })()
            """)
    }

    /// What typing amounts to: the caret in a run, and a `beforeinput` the
    /// editor takes and applies itself - the same way odrcore's own tests type.
    private func typeIntoTheFirstRun() {
        _ = evaluate(
            """
            (function () {
                var run = document.querySelector('x-s[data-odr-id]');
                var range = document.createRange();
                range.setStart(run.firstChild, 0);
                range.collapse(true);
                var selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                run.dispatchEvent(new InputEvent('beforeinput', {
                    inputType: 'insertText',
                    data: '\(Self.editedText) ',
                    bubbles: true,
                    cancelable: true
                }));
            })()
            """)

        // the log is reported on the next turn
        _ = XCTWaiter.wait(for: [expectation(description: "the editor to log it")], timeout: 0.5)
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
            documentURL.path, into: temporaryDirectory, with: nil, editable: false, scope: .document)

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
