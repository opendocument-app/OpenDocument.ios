import XCTest

@testable import OpenDocumentReader

/// The document's name in the tool bar: what it says, and that saying it costs
/// the buttons nothing.
class DocumentTitleTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DocumentViewController!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil

        super.tearDown()
    }

    /// The file need not exist: the name is read from the URL, and the bar shows
    /// it before the document is opened.
    private func present(_ name: String, width: CGFloat = 390) throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: DocumentViewController.self))
        controller = try XCTUnwrap(
            storyboard.instantiateViewController(withIdentifier: "TextDocumentViewController")
                as? DocumentViewController)

        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        controller.document = Document(fileURL: documents.appendingPathComponent(name))

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.layoutIfNeeded()
    }

    func testTheBarShowsTheNameWithoutTheExtension() throws {
        try present("Quarterly report.odt")

        XCTAssertEqual(controller.documentTitleLabel.text, "Quarterly report")
        XCTAssertTrue(controller.documentTitleLabel.isDescendant(of: controller.toolBar))
    }

    /// The name is what a reader recognises the file by, so a dot in it is part
    /// of the name and not an extension.
    func testOnlyTheLastDotIsTheExtension() throws {
        try present("Minutes 12.03.odt")

        XCTAssertEqual(controller.documentTitleLabel.text, "Minutes 12.03")
    }

    /// Every button a document can have, as a bar that can edit and search
    /// shows them.
    private func showEveryButton() {
        controller.canEdit = true
        controller.canSearch = true
        controller.view.layoutIfNeeded()
    }

    /// Where a button is drawn, read through a private key: the bar has no
    /// public way to say. The iOS 26 bar does not draw a button put back into it
    /// while the window is a test's, so there the test cannot look.
    private func frame(of item: UIBarButtonItem) throws -> CGRect {
        guard let view = item.value(forKey: "view") as? UIView, view.window != nil, view.bounds.width > 0 else {
            throw XCTSkip("the bar did not draw this button")
        }
        return view.convert(view.bounds, to: controller.toolBar)
    }

    /// The bug this guards: a long name pushed the buttons off the end of the
    /// bar.
    func testALongNameLeavesTheButtonsInPlace() throws {
        try present("Quarterly report.odt", width: 375)
        let short = (try frame(of: controller.barButtonItem), try frame(of: controller.menuButton))
        window.isHidden = true

        try present("Quarterly report for the whole board, final revision, with appendices.odt", width: 375)
        let long = (try frame(of: controller.barButtonItem), try frame(of: controller.menuButton))

        XCTAssertEqual(short.0, long.0)
        XCTAssertEqual(short.1, long.1)
    }

    func testALongNameIsCutShortBetweenTheButtons() throws {
        for width: CGFloat in [375, 390, 402] {
            try present("Quarterly report for the whole board, final revision, with appendices.odt", width: width)
            showEveryButton()

            let label = controller.documentTitleLabel
            let name = label.frame

            XCTAssertLessThan(name.width, label.text!.size(withAttributes: [.font: label.font!]).width)
            for item in controller.toolBar.items ?? [] where item.image != nil {
                let button = try frame(of: item)
                XCTAssertFalse(name.intersects(button), "\(width)")
            }

            window.isHidden = true
        }
    }

    /// The bar is the same width whoever is in it, so a name has less room when
    /// there are more buttons to leave room for.
    func testMoreButtonsLeaveTheNameLessRoom() throws {
        try present("Quarterly report.odt")

        let withTwo = controller.documentTitleLabel.bounds.width

        showEveryButton()

        XCTAssertLessThan(controller.documentTitleLabel.bounds.width, withTwo)
    }
}
