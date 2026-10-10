import XCTest

@testable import OpenDocumentReader

class PrintPaperTests: XCTestCase {
    private let temporaryDirectory = NSTemporaryDirectory()

    private func fixture(_ name: String, _ pathExtension: String) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let url = documentsURL.appendingPathComponent(name + "." + pathExtension)
        try? FileManager.default.removeItem(at: url)
        let bundlePath = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: name, ofType: pathExtension))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: url)
        return url
    }

    private func translated(_ url: URL, password: String? = nil) throws -> CoreWrapper {
        let wrapper = CoreWrapper()
        try wrapper.translate(
            url.path, into: temporaryDirectory, with: password, editable: false, scope: .document)
        return wrapper
    }

    func testLengthsBecomePoints() {
        XCTAssertEqual(PrintPaper.points(8.5, unit: "in"), 612)
        XCTAssertEqual(try XCTUnwrap(PrintPaper.points(21, unit: "cm")), 595.28, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(PrintPaper.points(297, unit: "mm")), 841.89, accuracy: 0.01)
        XCTAssertEqual(PrintPaper.points(96, unit: "px"), 72)
        XCTAssertNil(PrintPaper.points(50, unit: "%"))
        XCTAssertNil(PrintPaper.points(0, unit: "cm"))
    }

    func testATextDocumentPrintsOnItsPage() throws {
        let wrapper = try translated(try fixture("test", "odt"))
        XCTAssertGreaterThan(wrapper.pageSize.height, wrapper.pageSize.width)
        XCTAssertFalse(wrapper.isPrintablePdf)
    }

    func testASlidePrintsLandscape() throws {
        let wrapper = try translated(try fixture("test", "odp"))
        XCTAssertGreaterThan(wrapper.pageSize.width, wrapper.pageSize.height)
        XCTAssertEqual(PaperChooser(pageSize: wrapper.pageSize).orientation, .landscape)
    }

    func testAPdfPrintsItself() throws {
        let url = try fixture("test", "pdf")
        let wrapper = try translated(url)
        XCTAssertTrue(wrapper.isPrintablePdf)
        XCTAssertNotNil(PrintPaper.firstPageSize(ofPDFAt: url))
    }

    func testAnEncryptedPdfPrintsThePage() throws {
        let wrapper = try translated(try fixture("test-encrypted", "pdf"), password: "secret")
        XCTAssertFalse(wrapper.isPrintablePdf)
    }
}
