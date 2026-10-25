import AppKit
import XCTest
@testable import Pir
import PirCore

private final class CursorProbeWindow: NSWindow {
    var onResize: (() -> Void)?
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        onResize?()
        super.setFrame(frameRect, display: flag)
    }
}

@MainActor
final class PinPanelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testShortTextUsesCompactNaturalSize() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PinPanel(content: .text("Hello 世界 😀"), screen: screen, offset: 0)
        defer { panel.close() }
        XCTAssertGreaterThanOrEqual(panel.frame.width, PinGeometry.minimumSize.width)
        XCTAssertLessThan(panel.frame.width, 250)
        XCTAssertLessThan(panel.frame.height, PinGeometry.minimumSize.height)
        XCTAssertGreaterThanOrEqual(panel.frame.height, PinTextSizing.minimumSize.height)
        let oneLine = PinTextSizing.naturalSize(for: "下相同的热键的", available: screen.visibleFrame.size)
        let trailingLine = PinTextSizing.naturalSize(for: "下相同的热键的\n", available: screen.visibleFrame.size)
        XCTAssertGreaterThan(trailingLine.height, oneLine.height)
    }

    func testMultilineTextMeasuresLineBreaksIndentationAndUnicode() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let source = "  第一行 😀\n\tsecond line\nthird\nfourth\nfifth\nsixth\n"
        let compact = PinTextSizing.naturalSize(for: "第一行", available: screen.visibleFrame.size)
        let panel = PinPanel(content: .text(source), screen: screen, offset: 0)
        defer { panel.close() }
        XCTAssertGreaterThan(panel.frame.height, compact.height)
        XCTAssertLessThan(panel.frame.height, 250)
        let text = try XCTUnwrap(descendant(NSTextView.self, in: try XCTUnwrap(panel.contentView)))
        XCTAssertEqual(text.string, source)
        XCTAssertNotNil(text.textLayoutManager)
    }

    func testLargeTextInitialSizingHasBoundedWorkAndScreenLimits() {
        let source = String(repeating: "  中文 😀\tlong content\n", count: 100_000)
        let available = NSSize(width: 800, height: 600)
        let started = CFAbsoluteTimeGetCurrent()
        let size = PinTextSizing.naturalSize(for: source, available: available)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        XCTAssertEqual(size, NSSize(width: 440, height: 360))
        XCTAssertLessThan(elapsed, 0.5, "Initial sizing must sample a bounded prefix")
        XCTAssertEqual(PinTextSizing.naturalSize(for: source, available: NSSize(width: 3000, height: 2000)),
                       NSSize(width: 560, height: 420))
    }

    func testTextRestorationRetainsSavedFrameAndRestoresMeasuredSize() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let source = "A small note"
        let saved = NSRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.minY + 40,
                           width: 350, height: 250)
        let panel = PinPanel(content: .text(source), screen: screen, offset: 0, restoredFrame: saved)
        defer { panel.close() }
        XCTAssertEqual(panel.frame, saved)
        panel.restoreNaturalSize()
        XCTAssertEqual(panel.frame.size, PinTextSizing.naturalSize(for: source, available: screen.visibleFrame.size))
    }

    func testResizeHitAreaAndCursorUseHalfWidthAcrossTextSubviews() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PinPanel(content: .text(String(repeating: "text\n", count: 100)), screen: screen, offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 200), display: true)
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(PinSurface.resizeInset, 6.5)
        let samples: [(NSPoint, ResizeEdges)] = [
            (NSPoint(x: 3, y: 100), .left), (NSPoint(x: 297, y: 100), .right),
            (NSPoint(x: 150, y: 3), .bottom), (NSPoint(x: 150, y: 197), .top),
            (NSPoint(x: 3, y: 3), [.left, .bottom]),
            (NSPoint(x: 297, y: 197), [.right, .top]),
            (NSPoint(x: 3, y: 197), [.left, .top]),
            (NSPoint(x: 297, y: 3), [.right, .bottom])
        ]
        for (point, edges) in samples {
            XCTAssertEqual(surface.edges(at: point), edges)
            XCTAssertTrue(surface.hitTest(surface.convert(point, to: surface.superview)) === surface)
            XCTAssertFalse(surface.resizeCursor(at: point) === NSCursor.arrow)
            let location = surface.convert(point, to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: location,
                                                       modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                       context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            surface.mouseMoved(with: event)
            XCTAssertTrue(NSCursor.current === surface.resizeCursor(at: point))
        }
        XCTAssertTrue(surface.edges(at: NSPoint(x: 8, y: 100)).isEmpty)
        XCTAssertTrue(surface.resizeCursor(at: NSPoint(x: 8, y: 100)) === NSCursor.iBeam)
        panel.setFrame(NSRect(x: 100, y: 100, width: 500, height: 300), display: true)
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.resizeCursor(at: NSPoint(x: 497, y: 150)) === NSCursor.resizeLeftRight)
        XCTAssertTrue(surface.edges(at: NSPoint(x: 297, y: 150)).isEmpty)
    }

    func testResizeDragKeepsDirectionalCursorWhileWindowFrameChanges() throws {
        let window = CursorProbeWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                                       styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = PinTextSizing.minimumSize
        let surface = PinSurface(content: .text("Resize cursor"))
        window.contentView = surface
        window.orderFrontRegardless()
        defer { window.close() }
        surface.layoutSubtreeIfNeeded()
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 297, y: 100),
                                                   modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let dragged = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 317, y: 100),
                                                      modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                                                      context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 317, y: 100),
                                                 modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        var seen = false
        window.onResize = { seen = NSCursor.current === NSCursor.resizeLeftRight }
        NSCursor.arrow.set()
        NSApp.postEvent(up, atStart: true)
        NSApp.postEvent(dragged, atStart: true)
        surface.mouseDown(with: down)
        XCTAssertTrue(seen)
        XCTAssertEqual(window.frame.width, 320, accuracy: 1)
    }

    func testNarrowPinKeepsTextViewportAndVerticalScrolling() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let source = String(repeating: "  leading spaces\n\tIndented 中文 😀\n", count: 200)
        let panel = PinPanel(content: .text(source), screen: screen, offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 120, height: 80), display: true)
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: content))
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertNotNil(text.textLayoutManager, "Pin text must retain TextKit 2 viewport layout")
        XCTAssertEqual(text.string, source)
        XCTAssertLessThanOrEqual(text.frame.width, scroll.contentSize.width + 1)
        XCTAssertTrue(scroll.hasVerticalScroller)
        text.scrollRangeToVisible(NSRange(location: (source as NSString).length - 1, length: 1))
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "The last line must remain reachable by vertical scrolling")
    }

    func testImageCoverFillsMismatchedAspectRatio() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 40,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 200, height: 40))
        image.addRepresentation(bitmap)
        let panel = PinPanel(content: .image(image), screen: screen, offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 120, height: 180), display: true)
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(descendant(PinImageView.self, in: content))
        XCTAssertEqual(imageView.layer?.contentsGravity, .resizeAspectFill)
        XCTAssertTrue(imageView.layer?.masksToBounds == true)
        XCTAssertEqual(imageView.bounds.size, content.bounds.size)
        XCTAssertNotNil(imageView.layer?.contents)
        let rendered = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 180,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rendered))
        imageView.layer?.render(in: context.cgContext)
        XCTAssertGreaterThan(rendered.colorAt(x: 60, y: 10)?.alphaComponent ?? 0, 0.95)
        XCTAssertGreaterThan(rendered.colorAt(x: 60, y: 170)?.alphaComponent ?? 0, 0.95)
    }

    func testImageEdgeTransparencyControlsSystemShadowAndClipping() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        for edgeAlpha: UInt8 in [0, 100, 255] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let pixels = try XCTUnwrap(bitmap.bitmapData)
            pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            for x in 0..<bitmap.pixelsWide {
                pixels[x * 4 + 3] = edgeAlpha
                pixels[(bitmap.pixelsHigh - 1) * bitmap.bytesPerRow + x * 4 + 3] = edgeAlpha
            }
            for y in 0..<bitmap.pixelsHigh {
                pixels[y * bitmap.bytesPerRow + 3] = edgeAlpha
                pixels[y * bitmap.bytesPerRow + (bitmap.pixelsWide - 1) * 4 + 3] = edgeAlpha
            }
            let image = NSImage(size: NSSize(width: 160, height: 100))
            image.addRepresentation(bitmap)
            let panel = PinPanel(content: .image(image), screen: screen, offset: 0)
            defer { panel.close() }
            XCTAssertEqual(panel.hasShadow, edgeAlpha == 255)
            XCTAssertEqual(panel.contentView?.layer?.cornerRadius, edgeAlpha == 255 ? 10 : 0)
            let imageView = try XCTUnwrap(descendant(PinImageView.self, in: try XCTUnwrap(panel.contentView)))
            XCTAssertEqual(imageView.layer?.contentsGravity, .resizeAspectFill)
        }
    }

    func testTransparencyProbeChecksEveryEdgeAndIgnoresInteriorCutouts() throws {
        let width = 160
        let height = 100
        for point in [(80, 0), (80, 99), (0, 50), (159, 50), (80, 50)] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let pixels = try XCTUnwrap(bitmap.bitmapData)
            pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            pixels[point.1 * bitmap.bytesPerRow + point.0 * 4 + 3] = 0
            let image = try XCTUnwrap(bitmap.cgImage)
            XCTAssertEqual(PinImageAppearance.hasTransparentEdges(in: image), point != (80, 50))
        }
    }

    func testHoverControlsHaveContrastOverWhiteAndBackdropDoesNotInterceptInput() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PinPanel(content: .text("Hover controls"), screen: screen, offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let backdrop = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
        let buttons = surface.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 3)
        XCTAssertTrue(backdrop.isHidden)
        XCTAssertTrue(buttons.allSatisfy(\.isHiddenOrHasHiddenAncestor))
        surface.mouseEntered(with: NSEvent())
        surface.layoutSubtreeIfNeeded()
        backdrop.layoutSubtreeIfNeeded()
        XCTAssertFalse(backdrop.isHidden)
        XCTAssertNil(backdrop.hitTest(NSPoint(x: 20, y: 20)))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(backdrop.bounds.width), pixelsHigh: Int(backdrop.bounds.height),
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: backdrop.bounds.size))
        backdrop.layer?.render(in: context)
        for x in 0..<bitmap.pixelsWide {
            for y in [0, bitmap.pixelsHigh - 1] {
                XCTAssertGreaterThan(bitmap.colorAt(x: x, y: y)?.redComponent ?? 0, 0.98,
                                     "The hover shade must fade to transparent at its horizontal boundaries")
            }
        }
        for y in 0..<bitmap.pixelsHigh {
            for x in [0, bitmap.pixelsWide - 1] {
                XCTAssertGreaterThan(bitmap.colorAt(x: x, y: y)?.redComponent ?? 0, 0.98,
                                     "The hover shade must fade to transparent at its vertical boundaries")
            }
        }
        for button in buttons {
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(button.contentTintColor, .white)
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: backdrop)
            let sampleY = bitmap.pixelsHigh - 1 - Int(center.y)
            let background = try XCTUnwrap(bitmap.colorAt(x: Int(center.x), y: sampleY)?.usingColorSpace(.deviceRGB))
            XCTAssertLessThan(background.redComponent, 0.6, "White controls need contrast against the shaded image")
            let rect = button.convert(button.bounds, to: surface)
            let target = surface.convert(NSPoint(x: rect.midX, y: rect.midY), to: surface.superview)
            XCTAssertTrue(surface.hitTest(target) === button)
            let originalFrame = button.frame
            let normalArea = try visibleIconArea(of: button)
            button.cell?.isHighlighted = true
            let pressedArea = try visibleIconArea(of: button)
            button.cell?.isHighlighted = false
            XCTAssertGreaterThan(pressedArea, normalArea, "Press feedback should enlarge the icon")
            XCTAssertEqual(button.frame, originalFrame)
        }
        surface.mouseExited(with: NSEvent())
        XCTAssertTrue(backdrop.isHidden)
        XCTAssertTrue(buttons.allSatisfy(\.isHiddenOrHasHiddenAncestor))
    }

    func testTransparentImageShowsDashedBoundsOnlyWhileHovered() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        for alpha: UInt8 in [0, 255] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.bitmapData?.initialize(repeating: alpha, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            let image = NSImage(size: NSSize(width: 160, height: 100))
            image.addRepresentation(bitmap)
            let panel = PinPanel(content: .image(image), screen: screen, offset: 0)
            defer { panel.close() }
            let surface = try XCTUnwrap(panel.contentView as? PinSurface)
            let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
            XCTAssertTrue(outline.isHidden)
            surface.mouseEntered(with: NSEvent())
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(outline.isHidden, alpha == 255)
            XCTAssertEqual(outline.frame, surface.bounds)
            XCTAssertNil(outline.hitTest(NSPoint(x: 2, y: 20)))
            let stroke = try XCTUnwrap(outline.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
            XCTAssertNotNil(stroke.lineDashPattern)
            XCTAssertNotNil(stroke.path)
            panel.setContentSize(NSSize(width: 300, height: 180))
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(outline.frame, surface.bounds)
            surface.mouseExited(with: NSEvent())
            XCTAssertTrue(outline.isHidden)
        }
    }

    func testLargeTextRepeatedResizeUsesTextKitTwoViewport() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let source = String(repeating: "  let value = 1234567890; // viewport layout\n\tIndented second line with 中文\n", count: 10_000)
        let panel = PinPanel(content: .text(source), screen: screen, offset: 0)
        defer { panel.close() }
        panel.orderFrontRegardless()
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: content))
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertNotNil(text.textLayoutManager)
        let started = CFAbsoluteTimeGetCurrent()
        for index in 0..<40 {
            panel.setFrame(NSRect(x: 100, y: 100, width: index.isMultiple(of: 2) ? 120 : 680, height: 240), display: true)
            content.layoutSubtreeIfNeeded()
            content.displayIfNeeded()
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        print("Pir viewport benchmark bytes=\(source.utf8.count) lines=20000 resizes=40 seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, 5, "Repeated resize must avoid synchronous whole-document layout")
        XCTAssertNotNil(text.textLayoutManager)
        XCTAssertEqual(text.string, source)
        XCTAssertLessThanOrEqual(text.frame.width, scroll.contentSize.width + 1)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.compactMap { descendant(type, in: $0) }.first
    }

    private func visibleIconArea(of button: NSButton) throws -> Int {
        button.needsDisplay = true
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 { count += 1 }
            }
        }
        return count
    }
}
