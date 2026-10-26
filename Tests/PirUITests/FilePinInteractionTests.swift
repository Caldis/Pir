import AppKit
import XCTest
import PirCore
@testable import Pir

@MainActor
final class FilePinInteractionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testFileHeaderMovesWindowWhileLayoutControlRemainsInteractive() throws {
        let panel = PinPanel(content: .files(FilePinContent(urls: [URL(fileURLWithPath: "/tmp/file")])),
                             screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView)
        surface.layoutSubtreeIfNeeded()
        let header = NSPoint(x: 18, y: surface.bounds.maxY - 34)
        XCTAssertTrue(surface.hitTest(header) === surface)
        let modes = try XCTUnwrap(descendant(NSSegmentedControl.self, in: surface))
        XCTAssertTrue(surface.hitTest(modes.convert(NSPoint(x: modes.bounds.midX, y: modes.bounds.midY), to: surface)) === modes)
    }

    func testRubberBandSelectsPartialIntersectionsAndCombinesModifiers() throws {
        let files = PinFilesView(content: FilePinContent(urls: (0..<6).map { URL(fileURLWithPath: "/tmp/file-\($0)") }))
        files.frame = NSRect(x: 0, y: 0, width: 304, height: 254)
        files.layoutSubtreeIfNeeded()
        let collection = try XCTUnwrap(descendant(FileCollectionView.self, in: files))
        let layout = try XCTUnwrap(collection.collectionViewLayout)
        layout.prepare()
        let first = IndexPath(item: 0, section: 0), second = IndexPath(item: 1, section: 0)
        let frame = try XCTUnwrap(layout.layoutAttributesForItem(at: first)).frame
        let intersection = NSRect(x: frame.minX + 3, y: frame.minY + 10, width: 3, height: 4)
        collection.updateBandSelection(in: intersection, initial: [], modifiers: [])
        XCTAssertEqual(collection.selectionIndexPaths, [first])
        collection.updateBandSelection(in: intersection, initial: [second], modifiers: .shift)
        XCTAssertEqual(collection.selectionIndexPaths, [first, second])
        collection.updateBandSelection(in: intersection, initial: [first, second], modifiers: .command)
        XCTAssertEqual(collection.selectionIndexPaths, [second])
    }

    func testFileMenuProvidesRequiredActionsAndOpenUsesEverySelectedURL() throws {
        let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]
        var opened: [URL] = []
        var actions = FilePinActions()
        actions.open = { opened.append($0); return true }
        let files = PinFilesView(content: FilePinContent(urls: urls), actions: actions)
        let collection = try XCTUnwrap(descendant(FileCollectionView.self, in: files))
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)]
        let menu = files.selectionMenu()
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title),
                       ["Open", "Move to Trash", "Get Info", "Rename", "Show in Finder", "Remove from list"].map(L))
        let open = try XCTUnwrap(menu.items.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(open.action), to: open.target, from: open))
        XCTAssertEqual(opened, urls)
    }

    func testRenamingUpdatesSharedReferencesAndKeepsContents() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("one.txt"), second = root.appendingPathComponent("two.txt")
        try Data("first".utf8).write(to: first); try Data("second".utf8).write(to: second)
        let files = PinFilesView(content: FilePinContent(urls: [first, second]))
        let other = PinFilesView(content: FilePinContent(urls: [first]))
        var updates = 0; other.onChange = { _ in updates += 1 }
        try files.renameFiles(at: [0], name: "renamed.txt")
        let renamed = root.appendingPathComponent("renamed.txt")
        XCTAssertEqual(files.content.urls, [renamed, second])
        XCTAssertEqual(other.content.urls, [renamed])
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(try Data(contentsOf: renamed), Data("first".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertThrowsError(try files.renameFiles(at: [0], name: "two.txt"))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        for name in ["", "../escape", "a/b", ".", "..", "a:b"] {
            XCTAssertThrowsError(try files.renameFiles(at: [0], name: name))
        }
    }

    func testBatchRenamePreservesExtensionsAndRejectsCollisionsBeforeMoving() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = [root.appendingPathComponent("one.txt"), root.appendingPathComponent("two.md")]
        for url in urls { try Data(url.lastPathComponent.utf8).write(to: url) }
        let files = PinFilesView(content: FilePinContent(urls: urls))
        try files.renameFiles(at: [0, 1], name: "Draft")
        XCTAssertEqual(files.content.urls.map(\.lastPathComponent), ["Draft 1.txt", "Draft 2.md"])
        XCTAssertEqual(try Data(contentsOf: files.content.urls[0]), Data("one.txt".utf8))
        let collision = root.appendingPathComponent("Final 2.md")
        try Data("existing".utf8).write(to: collision)
        XCTAssertThrowsError(try files.renameFiles(at: [0, 1], name: "Final"))
        XCTAssertTrue(files.content.urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(try Data(contentsOf: collision), Data("existing".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".pir-rename-") })
    }

    func testPartialTrashRemovesOnlySuccessfulURLsAcrossPins() throws {
        let first = URL(fileURLWithPath: "/tmp/first.txt"), second = URL(fileURLWithPath: "/tmp/second.txt")
        var actions = FilePinActions()
        actions.recycle = { urls, completion in
            XCTAssertEqual(urls, [first, second])
            completion([first: URL(fileURLWithPath: "/tmp/trash/first.txt")], CocoaError(.fileWriteNoPermission))
        }
        let files = PinFilesView(content: FilePinContent(urls: [first, second]), actions: actions)
        let other = PinFilesView(content: FilePinContent(urls: [first]))
        var empty = false; other.onEmpty = { empty = true }
        var completed = false
        files.trashFiles(at: [0, 1]) { error in completed = true; XCTAssertNotNil(error) }
        XCTAssertTrue(completed)
        XCTAssertTrue(empty)
        XCTAssertEqual(files.content.urls, [second])
    }

    func testDirectoryChangesUpdateDescendantsWithComponentBoundaries() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let child = directory.appendingPathComponent("child.txt")
        try Data("child".utf8).write(to: child)
        let sibling = root.appendingPathComponent("folder-other/child.txt")
        let files = PinFilesView(content: FilePinContent(urls: [directory]))
        let other = PinFilesView(content: FilePinContent(urls: [child, sibling]))
        try files.renameFiles(at: [0], name: "renamed")
        let renamed = root.appendingPathComponent("renamed", isDirectory: true)
        XCTAssertEqual(other.content.urls, [renamed.appendingPathComponent("child.txt"), sibling])
        NotificationCenter.default.post(name: FilePinReferenceChange.notification,
                                        object: FilePinReferenceChange(removed: [renamed]))
        XCTAssertEqual(other.content.urls, [sibling])
    }

    func testRenameUsesCapturedURLsAfterEarlierReferenceDisappears() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = ["one.txt", "two.txt", "three.txt"].map { root.appendingPathComponent($0) }
        for url in urls { try Data(url.lastPathComponent.utf8).write(to: url) }
        let files = PinFilesView(content: FilePinContent(urls: urls))
        let captured = [urls[1]]
        NotificationCenter.default.post(name: FilePinReferenceChange.notification,
                                        object: FilePinReferenceChange(removed: [urls[0]]))
        try files.renameFiles(urls: captured, name: "renamed.txt")
        XCTAssertEqual(files.content.urls.map(\.lastPathComponent), ["renamed.txt", "three.txt"])
        XCTAssertEqual(try Data(contentsOf: urls[2]), Data("three.txt".utf8))
    }

    private func fixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pir-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let value = view as? T { return value }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }
}
