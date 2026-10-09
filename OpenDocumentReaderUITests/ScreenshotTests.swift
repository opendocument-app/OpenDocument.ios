import XCTest

/// Capture each store screen in a separate launch with -ODRScreenshot <screen>.
/// Fastlane repeats the test for each device and locale.
final class ScreenshotTests: XCTestCase {

    /// Each picture's name, and the screen it is of. The number is the place
    /// in the store. Lite's edit takes the place of Pro's in Lite's listing,
    /// so both are `04`.
    private static let pictures = [
        ("01-browser", "browser"),
        ("02-text", "text"),
        ("03-sheet", "sheet"),
        ("04-edit", "edit"),
        ("04-edit-lite", "edit-lite"),
        ("05-pdf", "pdf"),
        ("06-office", "office"),
    ]

    /// Long, because it covers translating a document on a simulator that is
    /// also running eleven other languages' worth of tests today.
    private let readyTimeout: TimeInterval = 180

    override func setUpWithError() throws {
        continueAfterFailure = false

        // A ceiling, not a target: six launches on a shared runner outrun
        // XCTest's ten minute default and get killed mid-test.
        executionTimeAllowance = 1800
    }

    @MainActor
    func testTakesTheStoreScreenshots() throws {
        let app = XCUIApplication()

        // the language and the region this run is for, once
        Snapshots.prepare(app)

        // Suppress the first-run swipe keyboard tutorial.
        app.launchArguments += ["-DidShowContinuousPathIntroduction", "1"]

        let arguments = app.launchArguments

        for (name, screen) in Self.pictures {
            app.launchArguments = arguments + ["-ODRScreenshot", screen]
            app.launch()

            let ready = app.descendants(matching: .any)["odr-screenshot-ready"]
            XCTAssertTrue(
                ready.waitForExistence(timeout: readyTimeout),
                "\(screen) never finished coming up, so there is nothing to photograph")

            if screen == "browser" {
                waitForTheFolderToFill(in: app)
            }

            if screen.hasPrefix("edit") {
                raiseTheKeyboard(in: app)
            }

            Snapshots.take(name)

            // rather than leaving it running: the next launch has to go through
            // didFinishLaunching again to be handed the next screen
            app.terminate()
        }
    }

    /// Wait until the Recents file count stabilizes.
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

    /// Tap document text to raise the keyboard; WebKit requires a user gesture.
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

    /// Dismiss the English keyboard tutorial if the launch flag did not suppress it.
    @MainActor
    private func dismissTheKeyboardTutorial(in app: XCUIApplication) {
        let continueButton = app.buttons["Continue"]

        // Keep this fallback wait short on runs without a tutorial.
        if continueButton.waitForExistence(timeout: 0.5) {
            continueButton.tap()
        }
    }
}
