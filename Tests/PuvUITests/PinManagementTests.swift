import AppKit
import XCTest
@testable import Puv
import PuvCore
import Combine

@MainActor
final class PinManagementTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testHiddenPinSurvivesRestartAndManagementDeleteRemovesFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        try first.show(.text("first line\nsecond line"))
        let summary = try XCTUnwrap(first.summaries.first)
        XCTAssertEqual(summary.title, "first line")
        first.setHidden(true, for: summary.id)
        XCTAssertTrue(try XCTUnwrap(first.summaries.first).isHidden)
        first.flushSession()
        first.closeAll()

        let second = PinManager(store: PinSessionStore(root: root))
        second.restoreSession()
        second.flushSession()
        defer { second.closeAll() }
        XCTAssertEqual(second.summaries.count, 1)
        XCTAssertTrue(try XCTUnwrap(second.summaries.first).isHidden)
        XCTAssertTrue(try XCTUnwrap(store.load().first).record.isHidden)
        second.setHidden(false, for: summary.id)
        XCTAssertFalse(try XCTUnwrap(second.summaries.first).isHidden)
        second.delete(summary.id)
        second.flushSession()
        XCTAssertTrue(second.summaries.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertFalse(remaining.contains { ["json", "content"].contains($0.pathExtension) })
    }

    func testRestoreNaturalSizeReportsFrameAndPreservesViewportBounds() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PinPanel(content: .text("text"), screen: screen, offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.minY + 30,
                              width: 120, height: 80), display: true)
        var reported: NSRect?
        panel.onFrameChange = { reported = $0 }
        panel.restoreNaturalSize()
        let expected = PinGeometry.initialSize(content: NSSize(width: 420, height: 300), available: screen.visibleFrame.size)
        XCTAssertEqual(panel.frame.size, expected)
        XCTAssertEqual(reported, panel.frame)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
    }

    func testImageRestoreUsesLogicalRetinaSize() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.addRepresentation(representation)
        let panel = PinPanel(content: .image(image), screen: screen, offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: 650, height: 450)), display: true)
        panel.restoreNaturalSize()
        XCTAssertEqual(panel.frame.size, PinGeometry.initialSize(content: NSSize(width: 400, height: 300), available: screen.visibleFrame.size))
    }

    func testImageThumbnailIsSmallAndReusedAcrossVisibilityChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PinManager(store: PinSessionStore(root: root))
        defer { manager.closeAll() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 300,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 300, height: 150))
        image.addRepresentation(bitmap)
        let ready = expectation(description: "Cached low resolution thumbnail")
        let observation = manager.$summaries.first { $0.first?.thumbnail != nil }.sink { _ in ready.fulfill() }
        try manager.show(.image(image))
        await fulfillment(of: [ready], timeout: 3)
        observation.cancel()
        let summary = try XCTUnwrap(manager.summaries.first)
        let thumbnail = try XCTUnwrap(summary.thumbnail)
        XCTAssertEqual(thumbnail.representations.first?.pixelsWide, 96)
        XCTAssertEqual(thumbnail.representations.first?.pixelsHigh, 96)
        manager.setHidden(true, for: summary.id)
        XCTAssertTrue(manager.summaries.first?.thumbnail === thumbnail)
        manager.delete(summary.id)
        manager.flushSession()
    }

    func testPreferencesUsesCompactThreePageToolbarAndFixedTitle() throws {
        let name = "PuvTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = PinManager()
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: manager)
        let controller = PreferencesWindowController(model: model)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        controller.showWindow(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentView?.bounds.size, NSSize(width: 450, height: 170))
        XCTAssertEqual(window.title, L("Preferences"))
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier.rawValue), ["general", "pins", "about"])
        let pins = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "pins" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(pins.action), to: pins.target, from: pins))
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "pins")
        XCTAssertEqual(window.title, L("Preferences"))
    }

    func testHoverControlsAreHiddenAndWinOverResizeHitArea() throws {
        let panel = PinPanel(content: .text("text"), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let close = try XCTUnwrap(descendantButtons(in: content).first { $0.identifier?.rawValue == "close-pin" })
        let restore = try XCTUnwrap(descendantButtons(in: content).first { $0.identifier?.rawValue == "restore-pin" })
        XCTAssertTrue(close.isHiddenOrHasHiddenAncestor)
        content.mouseEntered(with: NSEvent())
        XCTAssertFalse(close.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(restore.isHiddenOrHasHiddenAncestor)
        let nearTop = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.maxY - 1), to: content.superview)
        XCTAssertTrue(content.hitTest(nearTop) === close)
        content.mouseExited(with: NSEvent())
        XCTAssertTrue(close.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(restore.isHiddenOrHasHiddenAncestor)
    }

    private func descendantButtons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(descendantButtons)
    }
}
