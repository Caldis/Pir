import AppKit
import XCTest
@testable import Puv
import PuvCore

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
