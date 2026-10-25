import AppKit
import XCTest
@testable import Puv
import PuvCore

@MainActor
final class PinPanelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
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
        print("Puv viewport benchmark bytes=\(source.utf8.count) lines=20000 resizes=40 seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, 5, "Repeated resize must avoid synchronous whole-document layout")
        XCTAssertNotNil(text.textLayoutManager)
        XCTAssertEqual(text.string, source)
        XCTAssertLessThanOrEqual(text.frame.width, scroll.contentSize.width + 1)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.compactMap { descendant(type, in: $0) }.first
    }
}
