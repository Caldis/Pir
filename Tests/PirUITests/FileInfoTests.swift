import AppKit
import XCTest
@testable import Pir

@MainActor
final class FileInfoTests: XCTestCase {
    func testInfoReadsFileMetadataAndSelectableValues() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Example 文件.txt")
        try Data("Pir".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)

        let controller = try FileInfoWindowController(url: url)
        defer { controller.close() }
        XCTAssertEqual(controller.details.name, url.lastPathComponent)
        XCTAssertEqual(controller.details.location, directory.path)
        XCTAssertEqual(controller.details.byteCount, 3)
        XCTAssertEqual(controller.details.permissions, "rw-r----- (0640)")
        XCTAssertNotNil(controller.details.created)
        XCTAssertNotNil(controller.details.modified)
        let content = try XCTUnwrap(controller.window?.contentView)
        let values = descendants(of: content).compactMap { $0 as? NSTextField }.filter(\.isSelectable)
        XCTAssertTrue(values.contains { $0.stringValue == url.lastPathComponent })
        XCTAssertTrue(values.contains { $0.stringValue == directory.path })
        XCTAssertTrue(values.allSatisfy { !$0.isEditable && $0.textColor == .labelColor })
    }

    func testIndependentWindowsDeliverOneCloseCallbackEach() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try FileInfoWindowController(url: url)
        let second = try FileInfoWindowController(url: url)
        XCTAssertFalse(first.window === second.window)
        var firstCloses = 0
        var secondCloses = 0
        first.onClose = { firstCloses += 1 }
        second.onClose = { secondCloses += 1 }
        first.close()
        XCTAssertEqual(firstCloses, 1)
        XCTAssertEqual(secondCloses, 0)
        second.close()
        XCTAssertEqual(secondCloses, 1)
    }

    func testMissingFileThrowsAndDirectorySizeAvoidsRecursiveTraversal() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try FileInfoWindowController(url: directory))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try FileInfoWindowController(url: directory)
        defer { controller.close() }
        XCTAssertTrue(controller.details.isDirectory)
        XCTAssertNil(controller.details.byteCount)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
