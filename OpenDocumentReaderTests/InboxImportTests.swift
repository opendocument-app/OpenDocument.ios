import XCTest

@testable import OpenDocumentReader

final class InboxImportTests: XCTestCase {
    func testDuplicateNamesPreserveBothDocuments() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = directory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("report.odt")
        let incoming = inbox.appendingPathComponent("report.odt")
        try Data("original".utf8).write(to: original)
        try Data("incoming".utf8).write(to: incoming)

        let imported = try SceneDelegate.importFromInbox(incoming, documents: directory)

        XCTAssertEqual(imported.lastPathComponent, "report (2).odt")
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: imported), Data("incoming".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
    }

    func testSimilarDirectoryNamesAreNotTheInbox() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let input = directory.appendingPathComponent("Inbox-backup/report.odt")

        XCTAssertEqual(try SceneDelegate.importFromInbox(input, documents: directory), input)
    }
}
