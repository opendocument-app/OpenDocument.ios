import XCTest

/// The pictures the App Store shows.
///
/// One launch per screen, each with `-ODRScreenshot <screen>`, which is the
/// app's own back door: it puts itself on that screen and stays there. Nothing
/// here taps anything, because everything there is to tap on the way - the
/// document browser - is Apple's UI in eleven languages.
///
/// `fastlane snapshot` runs this once per language per device and collects what
/// it writes. `scripts/store-screenshots.py` then checks the set and stages it
/// for the release; the names below are the names it expects, and their order is
/// the order the store shows them in.
final class ScreenshotTests: XCTestCase {

    /// Long, because it covers translating a document on a simulator that is
    /// also running eleven other languages' worth of tests today.
    private let readyTimeout: TimeInterval = 180

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTakesTheStoreScreenshots() throws {
        let app = XCUIApplication()

        // adds the language, the locale and fastlane's own arguments, once
        setupSnapshot(app)

        // The keyboard offers to teach swipe typing the first time it comes up
        // on a fresh simulator, over the keyboard the edit screenshot is of.
        // Told here that it has already been shown, so nothing has to be tapped
        // away in a language this test cannot read.
        app.launchArguments += ["-DidShowContinuousPathIntroduction", "1"]

        let arguments = app.launchArguments

        for (index, screen) in ["browser", "text", "sheet", "edit", "pdf", "office"].enumerated() {
            app.launchArguments = arguments + ["-ODRScreenshot", screen]
            app.launch()

            let ready = app.descendants(matching: .any)["odr-screenshot-ready"]
            XCTAssertTrue(
                ready.waitForExistence(timeout: readyTimeout),
                "\(screen) never finished coming up, so there is nothing to photograph")

            if screen == "browser" {
                waitForTheFolderToFill(in: app)
            }

            if screen == "edit" {
                raiseTheKeyboard(in: app)
            }

            snapshot(String(format: "%02d-%@", index + 1, screen))

            // rather than leaving it running: the next launch has to go through
            // didFinishLaunching again to be handed the next screen
            app.terminate()
        }
    }

    /// Waits for the browser to have listed the documents.
    ///
    /// Recents is filled by the system a few at a time and the app cannot say
    /// when it is done, so this waits for the count to stop growing. The first
    /// cell is not the end of it.
    @MainActor
    private func waitForTheFolderToFill(in app: XCUIApplication) {
        let cells = app.collectionViews.cells

        XCTAssertTrue(
            cells.firstMatch.waitForExistence(timeout: 60),
            "the browser never listed the documents")

        let deadline = Date().addingTimeInterval(60)
        var listed = 0
        var stillFor = 0

        // three seconds, not one and a half: it has been seen to pause for two
        // beats and then hand over the last two files
        while stillFor < 6, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)

            let count = cells.count
            stillFor = count == listed ? stillFor + 1 : 0
            listed = count
        }
    }

    /// Taps into the text of the document being edited.
    ///
    /// A real tap, not a focus call from the app: WebKit only raises the
    /// keyboard for a gesture it saw, so an edit staged entirely in code sets a
    /// caret and nothing else.
    ///
    /// Where the text is depends on the page, and a tap into its margin reaches
    /// nothing, so this works down the page until the keyboard answers rather
    /// than betting the run on one offset.
    @MainActor
    private func raiseTheKeyboard(in app: XCUIApplication) {
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "the edit has no page to tap into")

        // near the top: the sample is a page of A4 with a few lines on it, so
        // most of what is on screen is the blank rest of the sheet
        for offset in [0.10, 0.14, 0.07, 0.18, 0.22, 0.28] {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offset)).tap()

            if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
                dismissTheKeyboardTutorial(in: app)

                return
            }
        }

        XCTFail("no tap down the page set a caret, so the keyboard never came up")
    }

    /// Belt and braces for the swipe typing panel, in case the launch argument
    /// stops being honoured. Only reaches an English keyboard, which is why it
    /// is the second line of defence and not the first.
    @MainActor
    private func dismissTheKeyboardTutorial(in app: XCUIApplication) {
        let continueButton = app.buttons["Continue"]

        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
        }
    }
}
