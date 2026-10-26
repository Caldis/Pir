import AppKit
import XCTest
@testable import Pir
import PirCore

@MainActor
final class PinSessionIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testTextAndWindowFrameSurviveManagerRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        let text = "  title\n\tIndented 中文 😀\n\nlast line"
        try first.show(.text(text))
        let panel = try XCTUnwrap(visiblePins().first)
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let frame = CGRect(x: visible.minX + 80, y: visible.minY + 100, width: 280, height: 200)
        panel.setFrame(frame, display: true)
        panel.userDidChangeFrame()
        first.flushSession()
        first.closeAll()

        let second = PinManager(store: PinSessionStore(root: root))
        second.restoreSession()
        // Termination flush also completes in-flight restoration before saving its snapshot.
        second.flushSession()
        defer { second.closeAll() }
        let restored = try XCTUnwrap(visiblePins().first)
        XCTAssertEqual(restored.frame.minX, frame.minX, accuracy: 0.01)
        XCTAssertEqual(restored.frame.minY, frame.minY, accuracy: 0.01)
        XCTAssertEqual(restored.frame.size, frame.size)
        let textView = try XCTUnwrap(descendant(NSTextView.self, in: try XCTUnwrap(restored.contentView)))
        XCTAssertEqual(textView.string, text)
        restored.close()
        second.flushSession()
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testNativeMoveNotificationPersistsWithoutExplicitGestureCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        try first.show(.text("Move only"))
        let panel = try XCTUnwrap(visiblePins().first)
        let moved = panel.frame.offsetBy(dx: 45, dy: -40)
        let willMove = Notification(name: NSWindow.willMoveNotification, object: panel)
        let didMove = Notification(name: NSWindow.didMoveNotification, object: panel)
        panel.windowWillMove(willMove)
        panel.setFrame(moved, display: true)
        panel.windowDidMove(didMove)
        first.flushSession()
        first.closeAll()
        let second = PinManager(store: store)
        defer { second.closeAll() }
        second.restoreSession()
        second.flushSession()
        let restored = try XCTUnwrap(visiblePins().first)
        XCTAssertEqual(restored.frame.minX, moved.minX, accuracy: 0.01)
        XCTAssertEqual(restored.frame.minY, moved.minY, accuracy: 0.01)
        XCTAssertEqual(restored.frame.size, moved.size)
    }

    func testProgrammaticDisplayMoveDoesNotRewriteSavedAnchor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let manager = PinManager(store: store)
        defer { manager.closeAll() }
        try manager.show(.text("Display migration"))
        manager.flushSession()
        let original = try XCTUnwrap(store.load().first?.record.anchor)
        let panel = try XCTUnwrap(visiblePins().first)
        panel.windowWillMove(Notification(name: NSWindow.willMoveNotification, object: panel))
        panel.setProgrammaticFrame(panel.frame.offsetBy(dx: 100, dy: -70))
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        manager.flushSession()
        XCTAssertEqual(try store.load().first?.record.anchor, original)
    }

    func testFinishedNativeMoveDoesNotClaimLaterSystemMovement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let manager = PinManager(store: store)
        defer { manager.closeAll() }
        try manager.show(.text("Completed drag"))
        let panel = try XCTUnwrap(visiblePins().first)
        let moved = panel.frame.offsetBy(dx: 35, dy: -25)
        panel.windowWillMove(Notification(name: NSWindow.willMoveNotification, object: panel))
        panel.setFrame(moved, display: true)
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        manager.flushSession()
        let userAnchor = try XCTUnwrap(store.load().first?.record.anchor)
        panel.setFrame(moved.offsetBy(dx: 90, dy: -60), display: true)
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        manager.flushSession()
        XCTAssertEqual(try store.load().first?.record.anchor, userAnchor)
    }

    func testNativeMoveWithoutMouseUpClearsAfterButtonRelease() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PinPanel(content: .text("Cancelled drag"), screen: screen, offset: 0)
        defer { panel.close() }
        var captured: [NSRect] = []
        panel.onFrameChange = { captured.append($0) }
        panel.windowWillMove(Notification(name: NSWindow.willMoveNotification, object: panel))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(captured, [panel.frame])
        panel.setFrame(panel.frame.offsetBy(dx: 20, dy: -20), display: true)
        panel.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        panel.capturePendingUserMove()
        XCTAssertEqual(captured.count, 1)
    }

    func testEditedTextCopiesCurrentContentAndSurvivesRestartIncludingEmptyNote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        try first.show(.text("original"))
        let panel = try XCTUnwrap(visiblePins().first)
        defer { first.closeAll() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let text = try XCTUnwrap(descendant(NSTextView.self, in: surface))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(text.isEditable)
        XCTAssertTrue(text.isSelectable)
        text.insertText("edited\nsecond line", replacementRange: NSRange(location: 0, length: 8))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        surface.copyContent(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "edited\nsecond line")
        first.flushSession()
        XCTAssertEqual(try store.load().first?.data, Data("edited\nsecond line".utf8))
        try first.pasteAgain(try XCTUnwrap(first.summaries.first?.id))
        XCTAssertEqual(first.summaries.count, 2)
        XCTAssertTrue(first.summaries.allSatisfy { $0.title == "edited" })
        first.delete(try XCTUnwrap(first.summaries.last?.id))
        text.insertText("", replacementRange: NSRange(location: 0, length: (text.string as NSString).length))
        first.flushSession()
        first.closeAll()
        let restored = PinManager(store: PinSessionStore(root: root))
        defer { restored.closeAll() }
        restored.restoreSession()
        restored.flushSession()
        XCTAssertEqual(restored.summaries.count, 1)
        let restoredPanel = try XCTUnwrap(visiblePins().first)
        let restoredText = try XCTUnwrap(descendant(NSTextView.self, in: try XCTUnwrap(restoredPanel.contentView)))
        XCTAssertEqual(restoredText.string, "")
    }

    func testFilePinPersistsLayoutAndRemovingReferencesKeepsSourceFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = [root.appendingPathComponent("first.txt"), root.appendingPathComponent("second.txt")]
        for url in urls { try Data("fixture".utf8).write(to: url) }
        let store = PinSessionStore(root: root.appendingPathComponent("session"))
        let first = PinManager(store: store)
        try first.show(.files(FilePinContent(urls: urls)))
        let panel = try XCTUnwrap(visiblePins().first)
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let files = try XCTUnwrap(descendant(PinFilesView.self, in: surface))
        XCTAssertTrue(panel.canBecomeKey)
        files.setLayout(.list)
        files.removeFiles(at: [0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let writer = try XCTUnwrap(files.collectionView(NSCollectionView(), pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)))
        pasteboard.writeObjects([writer])
        XCTAssertEqual(pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], [urls[1]])
        surface.copyContent(to: pasteboard)
        XCTAssertEqual(pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], [urls[1]])
        first.flushSession()
        first.closeAll()
        let second = PinManager(store: store)
        defer { second.closeAll() }
        second.restoreSession()
        second.flushSession()
        XCTAssertEqual(second.summaries.first?.kind, .files)
        let restoredPanel = try XCTUnwrap(visiblePins().first)
        let restored = try XCTUnwrap(descendant(PinFilesView.self, in: try XCTUnwrap(restoredPanel.contentView)))
        XCTAssertEqual(restored.content, FilePinContent(urls: [urls[1]], layout: .list))
        restored.removeFiles(at: [0])
        second.flushSession()
        XCTAssertTrue(second.summaries.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testImagePointSizeAndPNGSurviveRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.bitmapData?.initialize(repeating: 255, count: rep.bytesPerRow * rep.pixelsHigh)
        let image = NSImage(size: NSSize(width: 200, height: 100))
        image.addRepresentation(rep)
        try first.show(.image(image))
        let expectedSize = try XCTUnwrap(visiblePins().first).frame.size
        first.flushSession()
        first.closeAll()
        let record = try XCTUnwrap(store.load().first)
        XCTAssertEqual(record.record.imagePointSize, NSSize(width: 200, height: 100))
        XCTAssertEqual(NSBitmapImageRep(data: record.data)?.pixelsWide, 400)
        let second = PinManager(store: PinSessionStore(root: root))
        second.restoreSession()
        second.flushSession()
        defer { second.closeAll() }
        XCTAssertEqual(try XCTUnwrap(visiblePins().first).frame.size, expectedSize)
    }

    func testFailedRestorationPreservesExistingSessionDuringFlushAndNewPins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        try first.show(.text("original session"))
        first.flushSession()
        first.closeAll()
        let original = try XCTUnwrap(store.load().first)

        let second = PinManager(store: FailingReadStore(base: store))
        second.restoreSession()
        second.flushSession()
        XCTAssertEqual(try store.load().map(\.record.id), [original.record.id])
        try second.show(.text("new pin after failed restore"))
        second.flushSession()
        XCTAssertEqual(try store.load().count, 2)
        try XCTUnwrap(visiblePins().first).close()
        second.flushSession()
        XCTAssertEqual(try store.load().map(\.record.id), [original.record.id])
        second.closeAll()
    }

    func testPartialRecoveryNeverDeletesTemporarilyUnreadablePins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        try first.show(.text("first saved pin"))
        try first.show(.text("temporarily unreadable pin"))
        first.flushSession()
        first.closeAll()
        let baseline = try store.load()
        XCTAssertEqual(baseline.count, 2)

        let second = PinManager(store: PartialReadStore(base: store))
        second.restoreSession()
        second.flushSession()
        XCTAssertEqual(visiblePins().count, 1)
        XCTAssertEqual(Set(try store.load().map(\.record.id)), Set(baseline.map(\.record.id)))
        try XCTUnwrap(visiblePins().first).close()
        second.flushSession()
        XCTAssertEqual(try store.load().count, 1, "Only the explicitly closed pin should be removed")
        second.closeAll()
    }

    private func visiblePins() -> [PinPanel] { NSApp.windows.compactMap { $0 as? PinPanel }.filter(\.isVisible) }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.compactMap { descendant(type, in: $0) }.first
    }
}

private final class FailingReadStore: PinSessionStorage {
    let base: PinSessionStore
    init(base: PinSessionStore) { self.base = base }
    func writeContent(_ data: Data, for id: UUID) throws { try base.writeContent(data, for: id) }
    func save(_ records: [PinRecord], removingMissing: Bool) throws { try base.save(records, removingMissing: removingMissing) }
    func load() throws -> [StoredPin] { throw CocoaError(.fileReadNoPermission) }
    func remove(_ id: UUID) throws { try base.remove(id) }
}

private final class PartialReadStore: PinSessionStorage {
    let base: PinSessionStore
    init(base: PinSessionStore) { self.base = base }
    func writeContent(_ data: Data, for id: UUID) throws { try base.writeContent(data, for: id) }
    func save(_ records: [PinRecord], removingMissing: Bool) throws { try base.save(records, removingMissing: removingMissing) }
    func load() throws -> [StoredPin] { Array(try base.load().prefix(1)) }
    func remove(_ id: UUID) throws { try base.remove(id) }
}
