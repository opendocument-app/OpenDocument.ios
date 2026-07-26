import XCTest

@testable import OpenDocumentReader

class PageTabBarTests: XCTestCase {
    private var tabBar: PageTabBar!
    private var valueChangedCount = 0

    override func setUp() {
        super.setUp()

        tabBar = PageTabBar(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        tabBar.addTarget(self, action: #selector(valueChanged), for: .valueChanged)

        valueChangedCount = 0
    }

    @objc private func valueChanged() {
        valueChangedCount += 1
    }

    private func collectionView() throws -> UICollectionView {
        try XCTUnwrap(tabBar.subviews.compactMap { $0 as? UICollectionView }.first)
    }

    private func tap(_ index: Int) throws {
        let collectionView = try collectionView()

        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(item: index, section: 0))
    }

    private func tabWidths() throws -> [CGFloat] {
        let collectionView = try collectionView()
        tabBar.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        return try tabBar.titles.indices.map { index in
            let attributes = try XCTUnwrap(
                collectionView.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))

            return attributes.frame.width
        }
    }

    func testSettingTitlesClearsTheSelection() {
        tabBar.titles = ["Alpha", "Beta"]
        tabBar.selectedIndex = 1

        tabBar.titles = ["Gamma", "Delta"]

        XCTAssertNil(tabBar.selectedIndex)
    }

    func testOutOfRangeSelectionIsIgnored() {
        tabBar.titles = ["Alpha", "Beta"]

        tabBar.selectedIndex = 5

        XCTAssertNil(tabBar.selectedIndex)
    }

    /// The document view selects the first page itself once a document is
    /// loaded, and must not have that echoed back as a page change.
    func testProgrammaticSelectionDoesNotNotify() {
        tabBar.titles = ["Alpha", "Beta"]

        tabBar.selectedIndex = 1

        XCTAssertEqual(tabBar.selectedIndex, 1)
        XCTAssertEqual(valueChangedCount, 0)
    }

    func testTapNotifiesOnce() throws {
        tabBar.titles = ["Alpha", "Beta", "Gamma"]

        try tap(2)

        XCTAssertEqual(tabBar.selectedIndex, 2)
        XCTAssertEqual(valueChangedCount, 1)
    }

    func testTappingTheSelectedTabDoesNotNotify() throws {
        tabBar.titles = ["Alpha", "Beta"]
        tabBar.selectedIndex = 0

        try tap(0)

        XCTAssertEqual(valueChangedCount, 0)
    }

    func testTabsShareTheWidthWhileTheyFit() throws {
        tabBar.titles = ["Alpha", "Beta", "Gamma"]

        for width in try tabWidths() {
            XCTAssertEqual(width, tabBar.bounds.width / 3, accuracy: 0.5)
        }
    }

    /// The control this replaced gave every tab the width of the longest title,
    /// so one long sheet name pushed all the others off screen.
    func testOneLongTitleDoesNotWidenTheOtherTabs() throws {
        tabBar.titles = ["Alpha", "Beta", "Q4 Consolidated Revenue Forecast"]

        let widths = try tabWidths()

        XCTAssertLessThan(widths[0], widths[2] / 2)
        XCTAssertLessThan(widths[1], widths[2] / 2)
    }
}

/// The document view reaches the tab bar through the storyboard, so these cover
/// the outlet and the custom class along with the behaviour.
class DocumentViewControllerPageTabsTests: XCTestCase {
    private var viewController: DocumentViewController!
    private var documentURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: DocumentViewController.self))

        viewController = try XCTUnwrap(
            storyboard.instantiateViewController(withIdentifier: "TextDocumentViewController") as? DocumentViewController)
        viewController.loadViewIfNeeded()

        // selecting a tab parses the document, so it has to be a real one
        documentURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("page-tabs.odt")
        try? FileManager.default.removeItem(at: documentURL)

        let bundlePath = try XCTUnwrap(Bundle(for: type(of: self)).path(forResource: "test", ofType: "odt"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: documentURL)
    }

    private func makeDocument(pageNames: [String]) -> Document {
        let document = Document(fileURL: documentURL)
        document.pageNames = pageNames

        return document
    }

    func testTabBarIsWiredUp() {
        XCTAssertNotNil(viewController.pageTabBar)
    }

    func testPagesFillTheTabBar() {
        viewController.documentPagesChanged(makeDocument(pageNames: ["Alpha", "Beta", "Gamma"]))

        XCTAssertEqual(viewController.pageTabBar.titles, ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(viewController.pageTabBar.selectedIndex, 0)
        XCTAssertFalse(viewController.pageTabBar.isHidden)
    }

    func testSinglePageHidesTheTabBar() {
        viewController.documentPagesChanged(makeDocument(pageNames: ["Alpha"]))

        XCTAssertTrue(viewController.pageTabBar.isHidden)
    }

    /// Pages used to be appended, so a second announcement left the tab bar
    /// showing every page twice.
    func testPagesAreReplacedNotAppended() {
        viewController.documentPagesChanged(makeDocument(pageNames: ["Alpha", "Beta"]))
        viewController.documentPagesChanged(makeDocument(pageNames: ["Gamma", "Delta"]))

        XCTAssertEqual(viewController.pageTabBar.titles, ["Gamma", "Delta"])
    }

    func testSelectingATabTurnsThePage() throws {
        let document = makeDocument(pageNames: ["Alpha", "Beta", "Gamma"])
        viewController.document = document
        viewController.documentPagesChanged(document)

        let tabBar = viewController.pageTabBar!
        let collectionView = try XCTUnwrap(tabBar.subviews.compactMap { $0 as? UICollectionView }.first)
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: IndexPath(item: 2, section: 0))

        XCTAssertEqual(document.page, 2)
    }
}

