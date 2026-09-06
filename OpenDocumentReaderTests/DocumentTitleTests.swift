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
    private func present(_ name: String) throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: DocumentViewController.self))
        controller = try XCTUnwrap(
            storyboard.instantiateViewController(withIdentifier: "TextDocumentViewController")
                as? DocumentViewController)

        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        controller.document = Document(fileURL: documents.appendingPathComponent(name))

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.layoutIfNeeded()
    }

    func testTheBarShowsTheNameWithoutTheExtension() throws {
        try present("Quarterly report.odt")

        XCTAssertEqual(controller.documentTitleLabel.text, "Quarterly report")
        XCTAssertTrue((controller.toolBar.items ?? []).contains { $0.customView === controller.documentTitleLabel })
    }

    /// The name is what a reader recognises the file by, so a dot in it is part
    /// of the name and not an extension.
    func testOnlyTheLastDotIsTheExtension() throws {
        try present("Minutes 12.03.odt")

        XCTAssertEqual(controller.documentTitleLabel.text, "Minutes 12.03")
    }

    func testTheNameSitsBetweenTheBackButtonAndTheRest() throws {
        try present("Quarterly report.odt")

        let items = try XCTUnwrap(controller.toolBar.items)
        let name = try XCTUnwrap(items.firstIndex { $0.customView === controller.documentTitleLabel })
        let back = try XCTUnwrap(items.firstIndex { $0 === controller.barButtonItem })
        let menu = try XCTUnwrap(items.firstIndex { $0 === controller.menuButton })

        XCTAssertTrue(back < name && name < menu)
    }

    /// What used to be the risk: a name long enough to push the buttons off the
    /// end of the bar.
    func testALongNameIsTruncatedRatherThanWidening() throws {
        try present("Quarterly report for the whole board, final revision.odt")

        let label = controller.documentTitleLabel

        XCTAssertLessThanOrEqual(label.bounds.width, label.maximumWidth)
        XCTAssertLessThan(label.maximumWidth, label.text!.size(withAttributes: [.font: label.font!]).width)
    }

    /// The bar is the same width whoever is in it, so a name has less room when
    /// there are more buttons to leave room for.
    func testFewerButtonsLeaveTheNameMoreRoom() throws {
        try present("Quarterly report.odt")

        let withEverything = controller.documentTitleLabel.maximumWidth

        controller.toolBar.items = (controller.toolBar.items ?? []).filter { $0 !== controller.menuButton }
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        XCTAssertGreaterThan(controller.documentTitleLabel.maximumWidth, withEverything)
    }

    func testTheLabelStopsGrowingAtItsMaximum() {
        let label = DocumentTitleLabel()
        label.text = String(repeating: "long name ", count: 20)

        label.maximumWidth = .greatestFiniteMagnitude
        let unbounded = label.intrinsicContentSize.width

        label.maximumWidth = 120

        XCTAssertGreaterThan(unbounded, 120)
        XCTAssertEqual(label.intrinsicContentSize.width, 120)
    }
}
