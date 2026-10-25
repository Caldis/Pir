import AppKit
import XCTest
@testable import Pir
import PirCore
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

    func testPasteAgainCopiesRestoredTextAndRetinaImageIndependently() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let original = PinManager(store: store)
        let text = "  original\n\tsecond line\n"
        try original.show(.text(text))
        let textID = try XCTUnwrap(original.summaries.first?.id)
        original.setHidden(true, for: textID)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 60,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        bitmap.size = NSSize(width: 40, height: 30)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        try original.show(.image(image))
        let imageID = try XCTUnwrap(original.summaries.last?.id)
        original.flushSession()
        original.closeAll()

        let restored = PinManager(store: PinSessionStore(root: root))
        defer { restored.closeAll() }
        restored.restoreSession()
        try restored.pasteAgain(textID)
        try restored.pasteAgain(imageID)
        restored.flushSession()
        XCTAssertEqual(restored.summaries.count, 4)
        XCTAssertTrue(try XCTUnwrap(restored.summaries.first { $0.id == textID }).isHidden)
        let copies = restored.summaries.filter { $0.id != textID && $0.id != imageID }
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.allSatisfy { !$0.isHidden })
        let saved = try store.load()
        XCTAssertEqual(saved.filter { $0.record.kind == .text }.map(\.data), [Data(text.utf8), Data(text.utf8)])
        XCTAssertEqual(saved.filter { $0.record.kind == .image }.map(\.record.imagePointSize),
                       [NSSize(width: 40, height: 30), NSSize(width: 40, height: 30)])
        restored.delete(textID)
        restored.delete(imageID)
        restored.flushSession()
        XCTAssertEqual(Set(try store.load().map(\.record.id)), Set(copies.map(\.id)))
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
        let expected = PinGeometry.initialSize(content: PinTextSizing.naturalSize(for: "text", available: screen.visibleFrame.size),
                                               available: screen.visibleFrame.size, minimum: PinTextSizing.minimumSize)
        XCTAssertEqual(panel.frame.size, expected)
        XCTAssertEqual(reported, panel.frame)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
    }

    func testClearAllRemovesVisibleAndHiddenPinsDuringSessionRestoration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let first = PinManager(store: store)
        try first.show(.text("Visible pin"))
        try first.show(.text("Hidden pin"))
        first.setHidden(true, for: try XCTUnwrap(first.summaries.last?.id))
        first.flushSession()
        first.closeAll()

        let second = PinManager(store: PinSessionStore(root: root))
        defer { second.closeAll() }
        second.restoreSession()
        second.deleteAll()
        second.flushSession()
        XCTAssertTrue(second.summaries.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .contains { ["json", "content"].contains($0.pathExtension) })

        let third = PinManager(store: PinSessionStore(root: root))
        defer { third.closeAll() }
        third.restoreSession()
        third.flushSession()
        XCTAssertTrue(third.summaries.isEmpty)
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
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = PinManager()
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: manager)
        let controller = PreferencesWindowController(model: model)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        controller.showWindow(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentLayoutRect.size, NSSize(width: 450, height: 181))
        XCTAssertEqual(window.title, L("Preferences"))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        XCTAssertEqual(tabs.tabStyle, .toolbar)
        XCTAssertEqual(tabs.tabView.tabViewType, .noTabsNoBorder)
        XCTAssertTrue(tabs.tabView.wantsLayer)
        let backdrop = try XCTUnwrap(tabs.view.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        let coverage = window.convertToScreen(backdrop.convert(backdrop.bounds, to: nil))
        XCTAssertGreaterThanOrEqual(coverage.maxY, window.frame.maxY - 1)
        XCTAssertLessThanOrEqual(coverage.minY, window.frame.minY + 1)
        for item in tabs.tabViewItems {
            let background = try XCTUnwrap(item.viewController?.view as? NSVisualEffectView)
            XCTAssertEqual(background.material, .toolTip)
            XCTAssertEqual(background.blendingMode, .behindWindow)
        }
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertEqual(toolbar.items.filter { $0.itemIdentifier != .flexibleSpace }.map(\.itemIdentifier.rawValue),
                       ["general", "pins", "updates", "about"])
        let pins = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "pins" })
        XCTAssertNil(pins.view)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(pins.action), to: pins.target, from: pins))
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "pins")
        XCTAssertEqual((window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex, 1)
        XCTAssertEqual(window.title, L("Preferences"))
    }

    func testClearedShortcutPersistsAndRecordingReactivatesBinding() throws {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let model = PreferencesModel(settings: settings, pins: PinManager())
        var active: HotKey? = .default
        model.onHotKeyClear = { active = nil }
        model.onHotKeyChange = { active = $0 }
        let page = GeneralPreferencesController(model: model)
        page.loadViewIfNeeded()
        let clear = try XCTUnwrap(descendantButtons(in: page.view).first {
            $0.accessibilityLabel() == L("Clear shortcut")
        })
        XCTAssertTrue(clear.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(clear.action), to: clear.target, from: clear))
        XCTAssertNil(active)
        XCTAssertFalse(model.hotKeyEnabled)
        XCTAssertFalse(SettingsStore(defaults: defaults).hotKeyEnabled)
        let reopened = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: PinManager())
        XCTAssertFalse(reopened.hotKeyEnabled)

        model.onHotKeyChange = { _ in throw HotKeyError.invalid }
        XCTAssertThrowsError(try model.setHotKey(.default))
        XCTAssertFalse(settings.hotKeyEnabled)
        XCTAssertNil(active)

        let replacement = HotKey(keyCode: 35, modifiers: [.command, .option])
        model.onHotKeyChange = { active = $0 }
        try model.setHotKey(replacement)
        XCTAssertEqual(active, replacement)
        XCTAssertTrue(SettingsStore(defaults: defaults).hotKeyEnabled)
        XCTAssertEqual(SettingsStore(defaults: defaults).hotKey, replacement)
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

    func testPreferencesErrorGetsSpaceAndKeepsWindowTopFixed() async throws {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: PinManager())
        let controller = PreferencesWindowController(model: model)
        defer { controller.close() }
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let initialHeight = window.contentLayoutRect.height
        let initialTop = window.frame.maxY
        let grew = expectation(forNotification: NSWindow.didResizeNotification, object: window) { _ in
            window.contentLayoutRect.height > initialHeight + 20
        }
        model.error = "Login item could not be changed. Move Pir to Applications and try again."
        await fulfillment(of: [grew], timeout: 3)
        XCTAssertEqual(window.frame.maxY, initialTop, accuracy: 1)
        let shrank = expectation(forNotification: NSWindow.didResizeNotification, object: window) { _ in
            window.contentLayoutRect.height <= initialHeight + 1
        }
        model.error = nil
        await fulfillment(of: [shrank], timeout: 3)
        XCTAssertEqual(window.frame.maxY, initialTop, accuracy: 1)
    }

    func testPreferencesPagesStayBelowToolbarAndKeepWindowTopFixed() async throws {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: PinManager())
        let controller = PreferencesWindowController(model: model)
        defer { controller.close() }
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        let initialTop = window.frame.maxY
        let root = try XCTUnwrap(window.contentViewController?.view)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        for (identifier, height) in [("pins", 270.0), ("about", 156.0), ("updates", 120.0), ("general", 181.0)] {
            let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == identifier })
            let resized = expectation(forNotification: NSWindow.didResizeNotification, object: window) { _ in
                abs(window.contentLayoutRect.height - height) < 1
            }
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
            await fulfillment(of: [resized], timeout: 3)
            root.layoutSubtreeIfNeeded()
            let page = try XCTUnwrap(tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController?.view)
            let pageFrame = page.convert(page.bounds, to: root)
            XCTAssertEqual(window.frame.maxY, initialTop, accuracy: 1)
            XCTAssertEqual(pageFrame.maxY, root.bounds.maxY, accuracy: 1)
            XCTAssertEqual(page.frame.height, height, accuracy: 1)
            XCTAssertTrue(root.bounds.contains(pageFrame))
        }
    }

    private func descendantButtons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(descendantButtons)
    }

    func testPreferencesContentAndBackdropStayAtWindowTopDuringAnimation() async throws {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: PinManager())
        let controller = PreferencesWindowController(model: model)
        defer { controller.close() }
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        let initialTop = window.frame.maxY
        var largestTopError: CGFloat = 0
        let contentTop = window.convertToScreen(window.contentLayoutRect).maxY
        var largestBackdropGap: CGFloat = 0
        for (identifier, samples) in [("pins", 45), ("general", 45), ("updates", 45), ("about", 45),
                                      ("pins", 3), ("updates", 3), ("general", 3), ("about", 45)] {
            let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == identifier })
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
            for _ in 0..<samples {
                let root = tabs.view
                root.layoutSubtreeIfNeeded()
                let page = try XCTUnwrap(tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController?.view)
                let pageRect = window.convertToScreen(page.convert(page.bounds, to: nil))
                let expectedTop = contentTop
                largestTopError = max(largestTopError, abs(pageRect.maxY - expectedTop))
                let background = try XCTUnwrap(root.subviews.compactMap { $0 as? NSVisualEffectView }.first)
                let covered = window.convertToScreen(background.convert(background.bounds, to: nil))
                largestBackdropGap = max(largestBackdropGap, window.frame.maxY - covered.maxY,
                                         covered.minY - window.frame.minY)
                XCTAssertEqual(window.frame.maxY, initialTop, accuracy: 1)
                try await Task.sleep(for: .milliseconds(8))
            }
        }
        XCTAssertLessThanOrEqual(largestTopError, 1, "Page top drift during the window animation")
        XCTAssertLessThanOrEqual(largestBackdropGap, 1, "Material must cover every intermediate window size")
    }

    func testShortcutKeycapsHavePaddingAndClearButtonMatchesHeight() throws {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: PinManager())
        try model.setHotKey(HotKey(keyCode: 121, modifiers: [.command, .option, .control, .shift]))
        let controller = PreferencesWindowController(model: model)
        controller.showWindow(nil)
        defer { controller.close() }
        let tabs = try XCTUnwrap(controller.window?.contentViewController as? NSTabViewController)
        let page = try XCTUnwrap(tabs.tabViewItems.first?.viewController?.view)
        page.layoutSubtreeIfNeeded()
        let recorder = try XCTUnwrap(page.subviews.compactMap { $0 as? RecorderButton }.first)
        let preview = try XCTUnwrap(recorder.subviews.compactMap { $0 as? KeyPreview }.first)
        let keycaps = preview.convert(preview.bounds, to: recorder)
        let alignment = recorder.alignmentRect(forFrame: recorder.bounds)
        XCTAssertEqual(keycaps.minX - alignment.minX, 4, accuracy: 0.5)
        XCTAssertLessThanOrEqual(keycaps.maxX, alignment.maxX - 4)
        XCTAssertEqual(keycaps.minY - alignment.minY, 4, accuracy: 0.5)
        XCTAssertEqual(alignment.maxY - keycaps.maxY, 4, accuracy: 0.5)
        XCTAssertEqual(preview.arrangedSubviews.count, 3)
        XCTAssertLessThan(try XCTUnwrap(preview.arrangedSubviews.first).frame.width, 85)
        for keycap in [preview.arrangedSubviews[0], preview.arrangedSubviews[2]] {
            let label = try XCTUnwrap(keycap.subviews.compactMap { $0 as? NSTextField }.first)
            XCTAssertEqual(keycap.frame.width, max(20, ceil(label.intrinsicContentSize.width) + 12), accuracy: 0.5)
        }
        let clear = try XCTUnwrap(descendantButtons(in: page).first { $0.accessibilityLabel() == L("Clear shortcut") })
        XCTAssertEqual(clear.frame.height, recorder.frame.height, accuracy: 0.5)
        XCTAssertEqual(clear.frame.midY, recorder.frame.midY, accuracy: 0.5)
    }
}
