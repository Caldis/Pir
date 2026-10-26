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

    func testFilePinsFitRowsAndKeepGridSpacingWhenResized() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let urls = (0..<6).map { URL(fileURLWithPath: "/tmp/pir-layout-\($0).txt") }
        let single = PinPanel(content: .files(FilePinContent(urls: [urls[0]])), screen: screen, offset: 0)
        defer { single.close() }
        XCTAssertLessThan(single.frame.height, 160)
        let panel = PinPanel(content: .files(FilePinContent(urls: urls)), screen: screen, offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        let files = try XCTUnwrap(descendant(PinFilesView.self, in: surface))
        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: files))
        for width: CGFloat in [304, 410] {
            panel.setContentSize(NSSize(width: width, height: panel.frame.height))
            surface.layoutSubtreeIfNeeded()
            let layout = try XCTUnwrap(collection.collectionViewLayout)
            layout.prepare()
            let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let second = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
            XCTAssertEqual(second.frame.minX - first.frame.maxX, 8, accuracy: 0.5)
            let item = try XCTUnwrap(files.collectionView(collection, itemForRepresentedObjectAt: IndexPath(item: 0, section: 0)))
            item.view.frame = first.frame
            item.view.layoutSubtreeIfNeeded()
            let icon = try XCTUnwrap(descendant(NSImageView.self, in: item.view))
            XCTAssertGreaterThanOrEqual(icon.frame.height, 56)
            XCTAssertEqual(icon.imageScaling, .scaleProportionallyUpOrDown)
        }
        surface.mouseEntered(with: NSEvent())
        let buttons = surface.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        XCTAssertEqual(Set(buttons.compactMap { $0.identifier?.rawValue }), ["restore-pin", "close-pin"])
        files.removeFiles(at: [1, 2, 3, 4, 5])
        XCTAssertLessThan(panel.frame.height, 160)
        files.setLayout(.list)
        XCTAssertLessThan(panel.frame.height, 100)
        panel.restoreNaturalSize()
        XCTAssertLessThan(panel.frame.height, 100)
    }

    func testTextAndFilePinsUsePreferencesMaterialBehindTransparentContent() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        for content: ClipboardContent in [.text("Material"), .files(FilePinContent(urls: [URL(fileURLWithPath: "/tmp/material.txt")]))] {
            let panel = PinPanel(content: content, screen: screen, offset: 0)
            defer { panel.close() }
            let surface = try XCTUnwrap(panel.contentView)
            surface.layoutSubtreeIfNeeded()
            let material = try XCTUnwrap(surface.subviews.first as? NSVisualEffectView)
            XCTAssertEqual(material.material, .toolTip)
            XCTAssertEqual(material.blendingMode, .behindWindow)
            XCTAssertEqual(material.frame, surface.bounds)
            let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: surface))
            XCTAssertFalse(scroll.drawsBackground)
            XCTAssertFalse(scroll.contentView.drawsBackground)
            if let text = descendant(NSTextView.self, in: surface) { XCTAssertFalse(text.drawsBackground) }
        }
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
        surface.hoverAnimationDuration = 0
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
        window.onResize = {
            seen = NSCursor.current === NSCursor.resizeLeftRight
            surface.mouseEntered(with: down)
            surface.mouseMoved(with: down)
            surface.mouseExited(with: down)
            XCTAssertTrue(NSCursor.current === NSCursor.resizeLeftRight)
        }
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
        XCTAssertTrue(imageView.imageLayer.frame.contains(imageView.bounds))
        XCTAssertEqual(imageView.imageLayer.frame.width / imageView.imageLayer.frame.height, 5, accuracy: 0.001)
        XCTAssertTrue(imageView.layer?.masksToBounds == true)
        XCTAssertEqual(imageView.bounds.size, content.bounds.size)
        XCTAssertNotNil(imageView.imageLayer.contents)
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
            panel.contentView?.layoutSubtreeIfNeeded()
            let imageFrame = imageView.imageLayer.frame
            XCTAssertGreaterThanOrEqual(imageFrame.width + 0.001, imageView.bounds.width)
            XCTAssertGreaterThanOrEqual(imageFrame.height + 0.001, imageView.bounds.height)
            XCTAssertEqual(imageFrame.width / imageFrame.height, 1.6, accuracy: 0.001)
            XCTAssertEqual(imageFrame.midX, imageView.bounds.midX, accuracy: 0.001)
            XCTAssertEqual(imageFrame.midY, imageView.bounds.midY, accuracy: 0.001)
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
        surface.hoverAnimationDuration = 0
        let backdrop = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
        let buttons = surface.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 3)
        let copy = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "copy-pin" }?.image)
        let close = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "close-pin" }?.image)
        XCTAssertLessThanOrEqual(copy.size.height, close.size.height)
        XCTAssertTrue(backdrop.isHidden)
        XCTAssertTrue(buttons.allSatisfy(\.isHiddenOrHasHiddenAncestor))
        surface.mouseEntered(with: NSEvent())
        surface.layoutSubtreeIfNeeded()
        backdrop.layoutSubtreeIfNeeded()
        XCTAssertFalse(backdrop.isHidden)
        XCTAssertEqual(backdrop.frame.minX, 0)
        XCTAssertEqual(buttons.map { $0.convert($0.bounds, to: surface).minX }.min(), 8)
        XCTAssertNil(backdrop.hitTest(NSPoint(x: 20, y: 20)))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(backdrop.bounds.width), pixelsHigh: Int(backdrop.bounds.height),
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: backdrop.bounds.size))
        backdrop.layer?.render(in: context)
        for button in buttons {
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(button.contentTintColor, .white)
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: backdrop)
            let sampleY = bitmap.pixelsHigh - 1 - Int(center.y)
            let background = try XCTUnwrap(bitmap.colorAt(x: Int(center.x), y: sampleY)?.usingColorSpace(.deviceRGB))
            XCTAssertLessThan(background.redComponent, 0.85, "White controls need contrast against the shaded image")
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
        surface.setHovered(false)
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
            surface.hoverAnimationDuration = 0
            let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
            XCTAssertTrue(outline.isHidden)
            surface.mouseEntered(with: NSEvent())
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(outline.isHidden, alpha == 255)
            XCTAssertEqual(outline.frame, surface.bounds)
            XCTAssertNil(outline.hitTest(NSPoint(x: 2, y: 20)))
            let stroke = try XCTUnwrap(outline.layer?.sublayers?.first?.sublayers?.compactMap { $0 as? CAShapeLayer }
                .first { $0.name == "pin-hover-outline-stroke" })
            XCTAssertEqual(stroke.shadowOpacity, 0)
            XCTAssertNotNil(stroke.lineDashPattern)
            XCTAssertNotNil(stroke.path)
            panel.setContentSize(NSSize(width: 300, height: 180))
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(outline.frame, surface.bounds)
            surface.setHovered(false)
            XCTAssertTrue(outline.isHidden)
        }
    }

    func testTransparentControlsStayOutsideImageAndFollowItsFrame() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PinPanel(content: .image(try transparentImage()), screen: screen, offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        let originalFrame = panel.frame
        surface.setHovered(true)
        let overlay = try XCTUnwrap(panel.childWindows?.first)
        let content = try XCTUnwrap(overlay.contentView)
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(overlay.frame.width, 116)
        XCTAssertFalse(panel.frame.intersects(overlay.frame))
        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertFalse(overlay.hasShadow)
        let buttons = content.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 4)
        let backdrop = try XCTUnwrap(content.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
        XCTAssertEqual(backdrop.layer?.cornerRadius, 10)
        XCTAssertTrue(backdrop.layer?.masksToBounds == true)
        panel.setFrame(originalFrame.offsetBy(dx: 20, dy: -20), display: true)
        XCTAssertEqual(overlay.frame.minX, panel.frame.minX, accuracy: 0.01)
        XCTAssertFalse(panel.frame.intersects(overlay.frame))
        surface.setHovered(false)
        XCTAssertEqual(overlay.alphaValue, 0)
        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertTrue(panel.childWindows?.contains(overlay) == true)
    }

    func testEveryContentKindRoutesEachEdgeAndCornerToSurface() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let transparent = try transparentImage()
        let solid = NSImage(size: NSSize(width: 200, height: 120), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let contents: [ClipboardContent] = [.image(transparent), .image(solid), .text("Edges"),
            .files(FilePinContent(urls: [URL(fileURLWithPath: "/tmp/edge.txt")]))]
        for content in contents {
            let panel = PinPanel(content: content, screen: screen, offset: 0)
            defer { panel.close() }
            panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 200), display: true)
            let surface = try XCTUnwrap(panel.contentView as? PinSurface)
            surface.layoutSubtreeIfNeeded()
            for point in [NSPoint(x: 3, y: 100), NSPoint(x: 297, y: 100), NSPoint(x: 150, y: 3), NSPoint(x: 150, y: 197),
                          NSPoint(x: 3, y: 3), NSPoint(x: 297, y: 197), NSPoint(x: 3, y: 197), NSPoint(x: 297, y: 3)] {
                XCTAssertTrue(surface.hitTest(surface.convert(point, to: surface.superview)) === surface)
                XCTAssertFalse(surface.edges(at: point).isEmpty)
                XCTAssertFalse(surface.resizeCursor(at: point) === NSCursor.arrow)
            }
        }
    }

    func testTransparentInputRingOnlyFillsResizeEdges() throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(surface.bounds.width),
            pixelsHigh: Int(surface.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        surface.layer?.render(in: context.cgContext)
        let edgeAlpha = try XCTUnwrap(bitmap.colorAt(x: 3, y: bitmap.pixelsHigh / 2)?.alphaComponent)
        XCTAssertEqual(edgeAlpha, PinSurface.transparentInputAlpha, accuracy: 0.5 / 255)
        XCTAssertLessThanOrEqual(edgeAlpha * 255, 1.01)
        XCTAssertEqual(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent, 0)
    }

    func testTransparentWindowServerHitTestingIncludesAlphaZeroEdges() throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        for point in [NSPoint(x: 3, y: panel.frame.height / 2), NSPoint(x: panel.frame.width - 3, y: 3),
                      NSPoint(x: panel.frame.width / 2, y: panel.frame.height - 3)] {
            let screenPoint = panel.convertPoint(toScreen: point)
            XCTAssertEqual(NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0), panel.windowNumber,
                           "WindowServer must deliver transparent edge input before NSView hitTest can resize")
        }
    }

    func testHoverAnimationReversesAndEndsAtLatestRequestedState() async throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
        surface.setHovered(true)
        surface.setHovered(false)
        surface.setHovered(true)
        try await Task.sleep(for: .milliseconds(240))
        XCTAssertFalse(outline.isHidden)
        XCTAssertEqual(outline.layer?.opacity, 1)
        surface.setHovered(false)
        try await Task.sleep(for: .milliseconds(240))
        XCTAssertTrue(outline.isHidden)
        XCTAssertEqual(outline.layer?.opacity, 0)
    }

    private func transparentImage() throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 200, height: 120))
        image.addRepresentation(bitmap)
        return image
    }

    func testControlsUseCloseFirstOrderForEveryContentKind() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let variants: [(ClipboardContent, [String])] = [
            (.text("Toolbar order"), ["close-pin", "restore-pin", "copy-pin"]),
            (.files(FilePinContent(urls: [URL(fileURLWithPath: "/tmp/toolbar.txt")])), ["close-pin", "restore-pin"]),
            (.image(try transparentImage()), ["close-pin", "restore-pin", "image-scaling-pin", "copy-pin"])
        ]
        for (content, identifiers) in variants {
            let panel = PinPanel(content: content, screen: screen, offset: 0)
            defer { panel.close() }
            let surface = try XCTUnwrap(panel.contentView as? PinSurface)
            surface.hoverAnimationDuration = 0
            surface.setHovered(true)
            XCTAssertEqual(try toolbarButtons(in: panel).compactMap { $0.identifier?.rawValue }, identifiers)
        }
    }

    func testCopyFeedbackRepeatsThenRestoresWithNamedPasteboard() async throws {
        let panel = PinPanel(content: .text("Copy feedback"), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(surface.copyContent(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Copy feedback")
        XCTAssertTrue(surface.isShowingCopySuccess)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(surface.copyContent(to: pasteboard))
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(surface.isShowingCopySuccess, "Repeated successful copies restart the feedback interval")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(surface.isShowingCopySuccess)
    }

    func testFailedCopyClearsSuccessFeedback() throws {
        let panel = PinPanel(content: .text("Failed copy"), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(surface.copyContent(to: pasteboard))
        XCTAssertTrue(surface.isShowingCopySuccess)
        XCTAssertFalse(surface.copyContent(to: RejectedPinCopyDestination()))
        XCTAssertFalse(surface.isShowingCopySuccess)
    }

    func testImageModeChangesKeepFrameAndCopyOriginalBitmap() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        bitmap.size = NSSize(width: 160, height: 40)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        let panel = PinPanel(content: .image(image), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 120, height: 180), display: true)
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        let imageView = try XCTUnwrap(descendant(PinImageView.self, in: surface))
        let frame = panel.frame
        var changes: [PinImageScaling] = []
        panel.onImageScalingChange = { changes.append($0) }
        XCTAssertEqual(panel.imageScaling, .cover)
        panel.setImageScaling(.fit, animated: false)
        XCTAssertEqual(panel.imageScaling, .fit)
        XCTAssertEqual(imageView.imageLayer.frame, NSRect(x: 0, y: 75, width: 120, height: 30))
        XCTAssertEqual(panel.frame, frame)
        panel.setImageScaling(.cover, animated: false)
        XCTAssertEqual(imageView.imageLayer.frame, NSRect(x: -300, y: 0, width: 720, height: 180))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertEqual(changes, [.fit, .cover])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(surface.copyContent(to: pasteboard))
        XCTAssertTrue(surface.isShowingCopySuccess)
        let copied = try XCTUnwrap(pasteboard.data(forType: .tiff).flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertEqual(copied.pixelsWide, 320)
        XCTAssertEqual(copied.pixelsHigh, 80)
    }

    func testFittedOpaqueImageKeepsTransparentLetterboxAndResizeInput() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 320, height: 80))
        image.addRepresentation(bitmap)
        let panel = PinPanel(content: .image(image), screen: try XCTUnwrap(NSScreen.main), offset: 0, imageScaling: .fit)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 200), display: true)
        panel.orderFrontRegardless()
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.layoutSubtreeIfNeeded()
        surface.displayIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let rendered = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rendered))
        surface.layer?.render(in: context.cgContext)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertEqual(rendered.colorAt(x: 100, y: 20)?.alphaComponent, 0)
        XCTAssertLessThanOrEqual((rendered.colorAt(x: 100, y: 3)?.alphaComponent ?? 1) * 255, 1.01)
        for point in [NSPoint(x: 100, y: 3), NSPoint(x: 100, y: 197)] {
            XCTAssertEqual(NSWindow.windowNumber(at: panel.convertPoint(toScreen: point), belowWindowWithWindowNumber: 0), panel.windowNumber)
            XCTAssertTrue(surface.hitTest(surface.convert(point, to: surface.superview)) === surface)
        }
    }

    func testImageModeTransitionResizesGeometryAndRenderedImage() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { throw XCTSkip("Motion is disabled") }
        let image = try opaqueWideImage()
        let panel = PinPanel(content: .image(image), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 200), display: true)
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(descendant(PinImageView.self, in: surface))
        let bitmap = try XCTUnwrap(view.imageLayer.contents as AnyObject?)
        let windowFrame = panel.frame
        panel.setImageScaling(.fit)
        let group = try XCTUnwrap(view.imageLayer.animation(forKey: "pin-image-scaling") as? CAAnimationGroup)
        let size = try XCTUnwrap(group.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" })
        let position = try XCTUnwrap(group.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "position" })
        let fromBounds = try XCTUnwrap(size.fromValue as? NSValue).rectValue
        let toBounds = try XCTUnwrap(size.toValue as? NSValue).rectValue
        let fromPosition = try XCTUnwrap(position.fromValue as? NSValue).pointValue
        let toPosition = try XCTUnwrap(position.toValue as? NSValue).pointValue
        XCTAssertEqual(fromBounds.size, NSSize(width: 800, height: 200))
        XCTAssertEqual(toBounds.size, NSSize(width: 200, height: 50))
        XCTAssertEqual(fromPosition, NSPoint(x: -300, y: 0))
        XCTAssertEqual(toPosition, NSPoint(x: 0, y: 75))
        XCTAssertEqual(panel.frame, windowFrame)
        XCTAssertFalse(group.animations?.compactMap { $0 as? CABasicAnimation }.contains { $0.keyPath == "opacity" } ?? false)
        view.imageLayer.removeAnimation(forKey: "pin-image-scaling")
        for (name, fraction) in [("cover", CGFloat(0)), ("middle", CGFloat(0.5)), ("fit", CGFloat(1))] {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.imageLayer.bounds = NSRect(x: 0, y: 0,
                width: fromBounds.width + (toBounds.width - fromBounds.width) * fraction,
                height: fromBounds.height + (toBounds.height - fromBounds.height) * fraction)
            view.imageLayer.position = NSPoint(x: fromPosition.x + (toPosition.x - fromPosition.x) * fraction,
                                               y: fromPosition.y + (toPosition.y - fromPosition.y) * fraction)
            CATransaction.commit()
            let rendered = try renderHoverArtwork(view)
            XCTAssertGreaterThan(rendered.colorAt(x: 100, y: 100)?.alphaComponent ?? 0, 0.95)
            if fraction == 0 { XCTAssertGreaterThan(rendered.colorAt(x: 100, y: 20)?.alphaComponent ?? 0, 0.95) }
            else { XCTAssertEqual(rendered.colorAt(x: 100, y: 20)?.alphaComponent, 0) }
            if fraction < 1 { XCTAssertGreaterThan(rendered.colorAt(x: 100, y: 60)?.alphaComponent ?? 0, 0.95) }
            else { XCTAssertEqual(rendered.colorAt(x: 100, y: 60)?.alphaComponent, 0) }
            XCTAssertTrue((view.imageLayer.contents as AnyObject?) === bitmap)
            XCTAssertEqual(view.imageLayer.opacity, 1)
            try exportHoverArtwork(rendered, name: "pin-image-resize-" + name)
        }
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 180), display: true)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.imageLayer.frame, NSRect(x: 0, y: 52.5, width: 300, height: 75))
        XCTAssertNil(view.imageLayer.animation(forKey: "pin-image-scaling"))
    }

    func testImageModeReversalStartsAtPresentedGeometry() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { throw XCTSkip("Motion is disabled") }
        let panel = PinPanel(content: .image(try opaqueWideImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 200), display: true)
        panel.orderFrontRegardless()
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(descendant(PinImageView.self, in: surface))
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        view.imageLayer.speed = 0
        view.imageLayer.timeOffset = 0
        panel.setImageScaling(.fit)
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        let first = try XCTUnwrap(view.imageLayer.animation(forKey: "pin-image-scaling") as? CAAnimationGroup)
        view.imageLayer.timeOffset = first.duration / 2
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let presented = try XCTUnwrap(view.imageLayer.presentation())
        let interruptedBounds = presented.bounds
        let interruptedPosition = presented.position
        XCTAssertGreaterThan(interruptedBounds.width, 200)
        XCTAssertLessThan(interruptedBounds.width, 800)
        panel.setImageScaling(.cover)
        let reversed = try XCTUnwrap(view.imageLayer.animation(forKey: "pin-image-scaling") as? CAAnimationGroup)
        let size = try XCTUnwrap(reversed.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" })
        let position = try XCTUnwrap(reversed.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "position" })
        XCTAssertEqual(try XCTUnwrap(size.fromValue as? NSValue).rectValue, interruptedBounds)
        XCTAssertEqual(try XCTUnwrap(position.fromValue as? NSValue).pointValue, interruptedPosition)
        XCTAssertEqual(try XCTUnwrap(size.toValue as? NSValue).rectValue.size, NSSize(width: 800, height: 200))
        XCTAssertEqual(view.imageLayer.opacity, 1)
        panel.setImageScaling(.fit, animated: false)
        XCTAssertNil(view.imageLayer.animation(forKey: "pin-image-scaling"))
        XCTAssertEqual(view.imageLayer.frame, NSRect(x: 0, y: 75, width: 200, height: 50))
    }

    private func opaqueWideImage() throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 400, height: 100))
        image.addRepresentation(bitmap)
        return image
    }

    func testRestoredImageModeInitializesWithoutChangingSavedFrame() throws {
        let saved = NSRect(x: 100, y: 100, width: 140, height: 180)
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0,
                             restoredFrame: saved, imageScaling: .fit)
        defer { panel.close() }
        XCTAssertEqual(panel.frame, saved)
        XCTAssertEqual(panel.imageScaling, .fit)
        let imageView = try XCTUnwrap(descendant(PinImageView.self, in: try XCTUnwrap(panel.contentView)))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(imageView.imageLayer.frame, NSRect(x: 0, y: 48, width: 140, height: 84))
    }

    private func toolbarButtons(in panel: PinPanel) throws -> [NSButton] {
        let surface = try XCTUnwrap(panel.contentView)
        let host = panel.childWindows?.first?.contentView ?? surface
        let stack = try XCTUnwrap(host.subviews.compactMap { $0 as? NSStackView }.first)
        return stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }

    func testTransparentToolbarUsesUniformRoundedDarkFill() throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        surface.setHovered(true)
        let overlay = try XCTUnwrap(panel.childWindows?.first)
        let host = try XCTUnwrap(overlay.contentView)
        host.layoutSubtreeIfNeeded()
        let backdrop = try XCTUnwrap(host.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
        backdrop.layoutSubtreeIfNeeded()
        XCTAssertFalse(overlay.hasShadow)
        XCTAssertEqual(overlay.frame.width, 116)
        XCTAssertEqual(backdrop.layer?.cornerRadius, 10)
        XCTAssertFalse(backdrop.layer?.sublayers?.contains { $0 is CAGradientLayer } ?? false)
        let rendered = try renderHoverArtwork(backdrop)
        for x in [20, 58, 95] {
            XCTAssertEqual(rendered.colorAt(x: x, y: 20)?.alphaComponent ?? 0, 0.5, accuracy: 1 / 255)
        }
        XCTAssertLessThan(rendered.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0.01)
        try exportHoverArtwork(try renderHoverArtwork(host), name: "pin-transparent-toolbar")
        try exportHoverArtwork(try renderHoverArtwork(host, background: .white), name: "pin-transparent-toolbar-white")
        try exportHoverArtwork(try renderHoverArtwork(host, background: NSColor(white: 0.08, alpha: 1)), name: "pin-transparent-toolbar-dark")
        let opaqueImage = NSImage(size: NSSize(width: 200, height: 120), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let opaque = PinPanel(content: .image(opaqueImage), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { opaque.close() }
        let opaqueSurface = try XCTUnwrap(opaque.contentView as? PinSurface)
        opaqueSurface.hoverAnimationDuration = 0
        opaqueSurface.setHovered(true)
        opaqueSurface.layoutSubtreeIfNeeded()
        let opaqueBackdrop = try XCTUnwrap(opaqueSurface.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
        XCTAssertFalse(opaqueBackdrop.layer?.sublayers?.contains { $0 is CAGradientLayer } ?? false)
        XCTAssertEqual(opaqueBackdrop.bounds.size, NSSize(width: 116, height: 40))
        XCTAssertEqual(try renderHoverArtwork(opaqueBackdrop).colorAt(x: 58, y: 20)?.alphaComponent ?? 0, 0.5, accuracy: 1 / 255)
        XCTAssertTrue(opaque.hasShadow)
        try exportHoverArtwork(try renderHoverArtwork(opaqueSurface, background: .white), name: "pin-opaque-toolbar-white")
        let text = PinPanel(content: .text("Internal backdrop"), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { text.close() }
        let internalBackdrop = try XCTUnwrap(text.contentView?.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
        XCTAssertTrue(internalBackdrop.layer?.sublayers?.contains { $0 is CAGradientLayer } == true)
    }

    func testOpaqueFitOutlineUpdatesForModeResizeAndHover() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 320, height: 80))
        image.addRepresentation(bitmap)
        let panel = PinPanel(content: .image(image), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 200), display: true)
        surface.layoutSubtreeIfNeeded()
        surface.setHovered(true)
        XCTAssertTrue(outline.isHidden, "Opaque cover has no transparent window margins")
        panel.setImageScaling(.fit, animated: false)
        XCTAssertFalse(outline.isHidden)
        XCTAssertEqual(outline.layer?.opacity, 1)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertTrue(panel.childWindows?.isEmpty ?? true)
        panel.setImageScaling(.cover, animated: false)
        XCTAssertTrue(outline.isHidden)
        panel.setImageScaling(.fit, animated: false)
        XCTAssertFalse(outline.isHidden)
        panel.setFrame(NSRect(x: 100, y: 100, width: 400, height: 100), display: true)
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(outline.isHidden, "Fit matching the image aspect ratio has no letterbox")
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 200), display: true)
        surface.layoutSubtreeIfNeeded()
        XCTAssertFalse(outline.isHidden, "Resizing restores bounds when fit leaves transparent margins")
        surface.setHovered(false)
        XCTAssertTrue(outline.isHidden)
        panel.setImageScaling(.cover, animated: false)
        panel.setImageScaling(.fit, animated: false)
        XCTAssertTrue(outline.isHidden, "Changing mode while not hovered keeps the outline hidden")
        surface.setHovered(true)
        XCTAssertFalse(outline.isHidden)
    }

    func testOutlineDarkContrastStaysOutsideWhiteOnEdgesAndCorners() throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        surface.setHovered(true)
        surface.layoutSubtreeIfNeeded()
        let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
        outline.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(outline.layer?.sublayers?.first { $0.name == "pin-hover-outline-content" })
        let whiteStroke = try XCTUnwrap(content.sublayers?.first { $0.name == "pin-hover-outline-stroke" })
        whiteStroke.isHidden = true
        let darkOnly = try renderHoverArtwork(outline)
        let width = darkOnly.pixelsWide
        let height = darkOnly.pixelsHigh
        var exteriorMaximum: CGFloat = 0
        for y in 16..<(height - 16) {
            exteriorMaximum = max(exteriorMaximum, darkOnly.colorAt(x: 1, y: y)?.alphaComponent ?? 0)
            XCTAssertEqual(darkOnly.colorAt(x: 3, y: y)?.alphaComponent, 0)
            XCTAssertEqual(darkOnly.colorAt(x: width - 4, y: y)?.alphaComponent, 0)
        }
        for x in 16..<(width - 16) {
            XCTAssertEqual(darkOnly.colorAt(x: x, y: 3)?.alphaComponent, 0)
            XCTAssertEqual(darkOnly.colorAt(x: x, y: height - 4)?.alphaComponent, 0)
        }
        XCTAssertGreaterThan(exteriorMaximum, 0.05)
        let safeInterior = CGPath(roundedRect: outline.bounds.insetBy(dx: 3.5, dy: 3.5), cornerWidth: 8, cornerHeight: 8, transform: nil)
        var cornerExterior = [CGFloat](repeating: 0, count: 4)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = darkOnly.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if safeInterior.contains(NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) { XCTAssertEqual(alpha, 0) }
                if x < 16, y < 16 { cornerExterior[0] = max(cornerExterior[0], alpha) }
                if x >= width - 16, y < 16 { cornerExterior[1] = max(cornerExterior[1], alpha) }
                if x < 16, y >= height - 16 { cornerExterior[2] = max(cornerExterior[2], alpha) }
                if x >= width - 16, y >= height - 16 { cornerExterior[3] = max(cornerExterior[3], alpha) }
            }
        }
        for alpha in cornerExterior { XCTAssertGreaterThan(alpha, 0.05) }
        try exportHoverArtwork(darkOnly, name: "pin-hover-outline-outside-dark-only")
        whiteStroke.isHidden = false
        try exportHoverArtwork(try renderHoverArtwork(outline, background: .white), name: "pin-hover-outline-one-sided-white")
        try exportHoverArtwork(try renderHoverArtwork(outline, background: NSColor(white: 0.08, alpha: 1)), name: "pin-hover-outline-one-sided-dark")
    }

    func testOpaqueImageToolbarInsetsAdaptWithoutClippingOrBlockingResizeEdges() throws {
        let panel = PinPanel(content: .image(try opaqueWideImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        for width: CGFloat in [120, 131, 132, 360] {
            for mode in [PinImageScaling.cover, .fit] {
                panel.setFrame(NSRect(x: 100, y: 100, width: width, height: 200), display: true)
                panel.setImageScaling(mode, animated: false)
                surface.setHovered(true)
                surface.layoutSubtreeIfNeeded()
                let backdrop = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-controls-backdrop" })
                let buttons = try toolbarButtons(in: panel)
                let compact = width < 132
                XCTAssertEqual(backdrop.frame.minX, 8)
                XCTAssertEqual(surface.bounds.maxY - backdrop.frame.maxY, 8)
                XCTAssertEqual(backdrop.frame.width, compact ? 102 : 116)
                XCTAssertEqual(backdrop.frame.height, 40)
                XCTAssertGreaterThanOrEqual(surface.bounds.maxX - backdrop.frame.maxX, 8)
                XCTAssertEqual(buttons.count, 4)
                for button in buttons {
                    let rect = button.convert(button.bounds, to: surface)
                    XCTAssertEqual(rect.size, NSSize(width: 22, height: 22))
                    XCTAssertTrue(backdrop.frame.contains(rect))
                    let center = NSPoint(x: rect.midX, y: rect.midY)
                    XCTAssertTrue(surface.hitTest(surface.convert(center, to: surface.superview)) === button)
                }
                let first = try XCTUnwrap(buttons.first)
                XCTAssertEqual(first.convert(first.bounds, to: surface).minX - backdrop.frame.minX, compact ? 4 : 8)
                for point in [NSPoint(x: backdrop.frame.minX + 1, y: backdrop.frame.midY),
                              NSPoint(x: backdrop.frame.maxX - 1, y: backdrop.frame.midY)] {
                    XCTAssertTrue(surface.hitTest(surface.convert(point, to: surface.superview)) === surface)
                    NSCursor.resizeLeftRight.set()
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: surface.convert(point, to: nil),
                        modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
                    surface.mouseMoved(with: event)
                    XCTAssertTrue(NSCursor.current === NSCursor.arrow)
                }
                for point in [NSPoint(x: 3, y: 100), NSPoint(x: 60, y: 197)] {
                    XCTAssertFalse(surface.edges(at: point).isEmpty)
                    XCTAssertTrue(surface.hitTest(surface.convert(point, to: surface.superview)) === surface)
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: surface.convert(point, to: nil),
                        modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
                    surface.mouseMoved(with: event)
                    XCTAssertTrue(NSCursor.current === surface.resizeCursor(at: point))
                    XCTAssertFalse(NSCursor.current === NSCursor.arrow)
                }
                if width == 120 || width == 360 {
                    let name = "pin-inset-toolbar-\(mode.rawValue)-\(Int(width))"
                    try exportHoverArtwork(try renderHoverArtwork(surface, background: .white), name: name + "-white")
                    try exportHoverArtwork(try renderHoverArtwork(surface, background: NSColor(white: 0.08, alpha: 1)), name: name + "-dark")
                }
            }
        }
    }

    func testHoverOutlineContrastsOnWhiteAndDarkWithinResizePerimeter() throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        surface.setHovered(true)
        surface.layoutSubtreeIfNeeded()
        let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
        outline.layoutSubtreeIfNeeded()
        let clear = try renderHoverArtwork(outline)
        for y in 7..<(clear.pixelsHigh - 7) {
            for x in 7..<(clear.pixelsWide - 7) {
                XCTAssertEqual(clear.colorAt(x: x, y: y)?.alphaComponent, 0)
            }
        }
        let white = try renderHoverArtwork(outline, background: .white)
        let dark = try renderHoverArtwork(outline, background: NSColor(white: 0.08, alpha: 1))
        let topWhite = (0..<7).flatMap { y in (12..<(white.pixelsWide - 12)).compactMap { white.colorAt(x: $0, y: y)?.redComponent } }
        let topDark = (0..<7).flatMap { y in (12..<(dark.pixelsWide - 12)).compactMap { dark.colorAt(x: $0, y: y)?.redComponent } }
        XCTAssertLessThan(try XCTUnwrap(topWhite.min()), 0.8)
        XCTAssertGreaterThan(try XCTUnwrap(topDark.max()), 0.8)
        XCTAssertEqual(white.colorAt(x: 100, y: 50)?.redComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(dark.colorAt(x: 100, y: 50)?.redComponent ?? 0, 0.08, accuracy: 0.01)
        try exportHoverArtwork(white, name: "pin-hover-outline-white")
        try exportHoverArtwork(dark, name: "pin-hover-outline-dark")
        try exportHoverArtwork(clear, name: "pin-hover-outline-transparent")
    }

    func testOutlineAnimationTransformKeepsEveryEdgeVisibleAtAllSizes() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { throw XCTSkip("Motion is disabled") }
        for size in [NSSize(width: 120, height: 80), NSSize(width: 800, height: 500)] {
            let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
            defer { panel.close() }
            panel.setFrame(NSRect(origin: NSPoint(x: 100, y: 100), size: size), display: true)
            let surface = try XCTUnwrap(panel.contentView as? PinSurface)
            surface.hoverAnimationDuration = 10
            surface.layoutSubtreeIfNeeded()
            surface.setHovered(true)
            let outline = try XCTUnwrap(surface.subviews.first { $0.identifier?.rawValue == "pin-hover-outline" })
            outline.layoutSubtreeIfNeeded()
            let content = try XCTUnwrap(outline.layer?.sublayers?.first { $0.name == "pin-hover-outline-content" })
            let animation = try XCTUnwrap(content.animation(forKey: "pin-hover-zoom") as? CABasicAnimation)
            let from = try XCTUnwrap(animation.fromValue as? NSValue).caTransform3DValue
            let to = try XCTUnwrap(animation.toValue as? NSValue).caTransform3DValue
            XCTAssertEqual(content.anchorPoint, .zero)
            XCTAssertLessThanOrEqual(from.m41, 2.001)
            XCTAssertLessThanOrEqual(from.m42, 2.001)
            XCTAssertEqual(from.m41, size.width * (1 - from.m11) / 2, accuracy: 0.001)
            XCTAssertEqual(from.m42, size.height * (1 - from.m22) / 2, accuracy: 0.001)
            outline.layer?.removeAnimation(forKey: "pin-hover")
            content.removeAnimation(forKey: "pin-hover-zoom")
            for (name, fraction) in [("from", CGFloat(0)), ("middle", CGFloat(0.5)), ("final", CGFloat(1))] {
                var frame = CATransform3DIdentity
                frame.m11 = from.m11 + (to.m11 - from.m11) * fraction
                frame.m22 = from.m22 + (to.m22 - from.m22) * fraction
                frame.m41 = from.m41 + (to.m41 - from.m41) * fraction
                frame.m42 = from.m42 + (to.m42 - from.m42) * fraction
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                content.transform = frame
                // Normalized opacity isolates the real animation transform's clipping at fade-in start.
                outline.layer?.opacity = 1
                CATransaction.commit()
                let rendered = try renderHoverArtwork(outline)
                let width = rendered.pixelsWide
                let height = rendered.pixelsHigh
                var edgeMaximum = [CGFloat](repeating: 0, count: 4)
                var interiorMaximum: CGFloat = 0
                for y in 0..<height {
                    for x in 0..<width {
                        let alpha = rendered.colorAt(x: x, y: y)?.alphaComponent ?? 0
                        if x < 7 { edgeMaximum[0] = max(edgeMaximum[0], alpha) }
                        if x >= width - 7 { edgeMaximum[1] = max(edgeMaximum[1], alpha) }
                        if y < 7 { edgeMaximum[2] = max(edgeMaximum[2], alpha) }
                        if y >= height - 7 { edgeMaximum[3] = max(edgeMaximum[3], alpha) }
                        if x >= 7, x < width - 7, y >= 7, y < height - 7 { interiorMaximum = max(interiorMaximum, alpha) }
                    }
                }
                for maximum in edgeMaximum { XCTAssertGreaterThan(maximum, 0.4, name + " must retain all four edges") }
                XCTAssertEqual(interiorMaximum, 0)
                try exportHoverArtwork(rendered, name: "pin-hover-outline-\(Int(size.width))-\(name)")
                let whiteStroke = try XCTUnwrap(content.sublayers?.first { $0.name == "pin-hover-outline-stroke" })
                whiteStroke.isHidden = true
                let darkOnly = try renderHoverArtwork(outline)
                var affine = CGAffineTransform(a: frame.m11, b: 0, c: 0, d: frame.m22, tx: frame.m41, ty: frame.m42)
                let interior = CGPath(roundedRect: outline.bounds.insetBy(dx: 3.5, dy: 3.5), cornerWidth: 8, cornerHeight: 8, transform: &affine)
                for y in 0..<height {
                    for x in 0..<width where interior.contains(NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                        XCTAssertEqual(darkOnly.colorAt(x: x, y: y)?.alphaComponent, 0)
                    }
                }
                try exportHoverArtwork(darkOnly, name: "pin-hover-shadow-\(Int(size.width))-\(name)")
                whiteStroke.isHidden = false
            }
        }
    }

    func testTransparentEdgeEntryMoveAndCursorEventsApplyDirectionalCursor() throws {
        let panel = PinPanel(content: .image(try transparentImage()), screen: try XCTUnwrap(NSScreen.main), offset: 0)
        defer { panel.close() }
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 200), display: true)
        let surface = try XCTUnwrap(panel.contentView as? PinSurface)
        surface.hoverAnimationDuration = 0
        surface.updateTrackingAreas()
        let always = surface.trackingAreas.filter { $0.options.contains(.activeAlways) }
        XCTAssertTrue(always.contains { $0.options.contains(.mouseEnteredAndExited) && $0.options.contains(.mouseMoved) })
        XCTAssertTrue(always.allSatisfy { !$0.options.contains(.cursorUpdate) })
        XCTAssertTrue(surface.trackingAreas.contains { $0.options.contains(.activeInActiveApp) && $0.options.contains(.cursorUpdate) })
        XCTAssertFalse(panel.canBecomeKey)
        let points = [NSPoint(x: 3, y: 100), NSPoint(x: 297, y: 100), NSPoint(x: 150, y: 3), NSPoint(x: 150, y: 197),
                      NSPoint(x: 3, y: 3), NSPoint(x: 297, y: 197), NSPoint(x: 3, y: 197), NSPoint(x: 297, y: 3)]
        for point in points {
            let location = surface.convert(point, to: nil)
            let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
            NSCursor.arrow.set()
            surface.mouseEntered(with: enter)
            XCTAssertTrue(NSCursor.current === surface.resizeCursor(at: point))
            let moved = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            NSCursor.arrow.set()
            surface.mouseMoved(with: moved)
            XCTAssertTrue(NSCursor.current === surface.resizeCursor(at: point))
            let update = try XCTUnwrap(NSEvent.enterExitEvent(with: .cursorUpdate, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
            NSCursor.arrow.set()
            surface.cursorUpdate(with: update)
            XCTAssertTrue(NSCursor.current === surface.resizeCursor(at: point))
        }
        let host = try XCTUnwrap(panel.childWindows?.first?.contentView)
        NSCursor.resizeLeftRight.set()
        host.mouseEntered(with: NSEvent())
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        NSCursor.resizeUpDown.set()
        host.mouseMoved(with: NSEvent())
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        NSCursor.resizeLeftRight.set()
        surface.mouseExited(with: NSEvent())
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
    }

    private func renderHoverArtwork(_ view: NSView, background: NSColor? = nil) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
            pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        if let background {
            context.cgContext.setFillColor(background.cgColor)
            context.cgContext.fill(view.bounds)
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.layer?.render(in: context.cgContext)
        return bitmap
    }

    private func exportHoverArtwork(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PIR_ARTWORK_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
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

private final class RejectedPinCopyDestination: PinCopyDestination {
    func clearContents() -> Int { 0 }
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool { false }
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { false }
}
