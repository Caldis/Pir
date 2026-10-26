import AppKit
import XCTest
import PirCore
@testable import Pir

@MainActor
final class FilePinSizingTests: XCTestCase {
    private let available = NSSize(width: 2000, height: 1200)
    private var hosts: [NSPanel] = []

    override func setUp() { super.setUp(); _ = NSApplication.shared }
    override func tearDown() {
        for host in hosts { host.close() }
        hosts.removeAll()
        super.tearDown()
    }

    func testNaturalScrollingGridKeepsThreeColumnsForBothScrollerStyles() throws {
        let content = fixture(count: 18)
        for style in [NSScroller.Style.legacy, .overlay] {
            let natural = PinFileSizing.naturalSize(for: content, available: available, scrollerStyle: style)
            let files = PinFilesView(content: content)
            files.frame = NSRect(origin: .zero, size: natural)
            let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: files))
            scroll.scrollerStyle = style
            let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: files))
            try settle(files)
            let layout = try XCTUnwrap(collection.collectionViewLayout)
            let frames = try (0..<4).map { try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))).frame }
            XCTAssertEqual(frames[0].minY, frames[2].minY)
            XCTAssertGreaterThan(frames[3].minY, frames[0].minY)
            XCTAssertLessThanOrEqual(frames[2].maxX + PinFileSizing.contentInset, scroll.contentSize.width)
            XCTAssertEqual(frames[1].minX - frames[0].maxX, 8)
            XCTAssertEqual(layout.collectionViewContentSize.width, scroll.contentSize.width)
            XCTAssertEqual(PinFileSizing.documentHeight(count: 18, layout: .icons, viewportWidth: scroll.contentSize.width),
                           layout.collectionViewContentSize.height)
            if style == .legacy {
                XCTAssertLessThan(scroll.contentSize.width, scroll.frame.width)
                XCTAssertGreaterThan(natural.width, 304)
            } else { XCTAssertEqual(natural.width, 304) }
        }
    }

    func testSharedViewportMetricsMatchRealScrollView() throws {
        for style in [NSScroller.Style.legacy, .overlay] {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 303, height: 370))
            scroll.borderType = .noBorder
            scroll.hasHorizontalScroller = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = false
            scroll.scrollerStyle = style
            scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 288, height: 1000))
            scroll.tile()
            XCTAssertEqual(PinFileSizing.viewportSize(for: scroll.frame.size, style: style, verticalScroller: true), scroll.contentSize)
        }
    }

    func testManualNarrowWidthUsesActualViewportInsteadOfForcingThreeColumns() throws {
        let content = fixture(count: 18)
        for style in [NSScroller.Style.legacy, .overlay] {
            let files = PinFilesView(content: content)
            let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: files))
            scroll.scrollerStyle = style
            for width: CGFloat in [250, 304] {
                let size = PinFileSizing.naturalSize(for: content, available: available, width: width, scrollerStyle: style)
                XCTAssertEqual(size.width, width)
                resize(files, to: size)
                try settle(files)
                let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: files))
                let layout = try XCTUnwrap(collection.collectionViewLayout)
                let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
                let third = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))).frame
                if width == 250 || style == .legacy { XCTAssertGreaterThan(third.minY, first.minY) }
                else { XCTAssertEqual(third.minY, first.minY) }
                XCTAssertEqual(layout.collectionViewContentSize.width, scroll.contentSize.width)
            }
        }
    }

    func testSmallNaturalGridDoesNotReserveUnusedLegacyScrollerWidth() throws {
        let content = fixture(count: 3)
        let legacy = PinFileSizing.naturalSize(for: content, available: available, scrollerStyle: .legacy)
        let overlay = PinFileSizing.naturalSize(for: content, available: available, scrollerStyle: .overlay)
        XCTAssertEqual(legacy, overlay)
        XCTAssertEqual(legacy, NSSize(width: 304, height: 152))
    }

    func testLegacyGridReleasesScrollerAfterRemovingItemsAndChangingLayout() throws {
        let files = PinFilesView(content: fixture(count: 18))
        let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: files))
        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: files))
        scroll.scrollerStyle = .legacy
        // Preserve a manually chosen width that originally needed a two-column scrolling layout.
        files.frame = NSRect(x: 0, y: 0, width: 304, height: 420)
        try settle(files)
        let original = try XCTUnwrap(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 2, section: 0)))
        XCTAssertGreaterThan(original.frame.minY, 4)
        files.removeFiles(at: Set(6..<18))
        refitHeight(files, style: .legacy)
        try settle(files)
        let first = try XCTUnwrap(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let third = try XCTUnwrap(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 2, section: 0)))
        XCTAssertEqual(first.frame.minY, third.frame.minY)
        XCTAssertEqual(files.frame.size, NSSize(width: 304, height: 254))
        XCTAssertEqual(scroll.contentSize.width, scroll.frame.width)
        files.setLayout(.list)
        refitHeight(files, style: .legacy)
        try settle(files)
        let row = try XCTUnwrap(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(row.frame.width + PinFileSizing.contentInset * 2, scroll.contentSize.width)
        files.removeFiles(at: Set(3..<6))
        files.setLayout(.icons)
        refitHeight(files, style: .legacy)
        try settle(files)
        XCTAssertEqual(files.frame.size, NSSize(width: 304, height: 152))
        XCTAssertEqual(scroll.contentSize.width, scroll.frame.width)
    }

    func testRestoredFilePanelRetainsSavedSizeAndUsesItsViewport() throws {
        let saved = NSRect(x: 100, y: 100, width: 250, height: 240)
        let panel = PinPanel(content: .files(fixture(count: 18)), screen: try XCTUnwrap(NSScreen.main), offset: 0, restoredFrame: saved)
        defer { panel.close() }
        let files = try XCTUnwrap(descendant(PinFilesView.self, in: try XCTUnwrap(panel.contentView)))
        let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: files))
        scroll.scrollerStyle = .legacy
        panel.contentView?.layoutSubtreeIfNeeded()
        try settle(files)
        XCTAssertEqual(panel.frame, saved)
        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: files))
        let third = try XCTUnwrap(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 2, section: 0)))
        XCTAssertGreaterThan(third.frame.minY, 4)
        XCTAssertEqual(collection.collectionViewLayout?.collectionViewContentSize.width, scroll.contentSize.width)
    }

    private func refitHeight(_ files: PinFilesView, style: NSScroller.Style) {
        resize(files, to: PinFileSizing.naturalSize(for: files.content, available: available, width: files.frame.width, scrollerStyle: style))
    }

    private func resize(_ files: PinFilesView, to size: NSSize) {
        if let window = files.window { window.setContentSize(size) }
        else { files.frame.size = size }
    }

    private func settle(_ files: PinFilesView) throws {
        if files.window == nil {
            let panel = NSPanel(contentRect: files.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = files
            panel.orderFrontRegardless()
            hosts.append(panel)
        }
        let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: files))
        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: files))
        for _ in 0..<6 {
            files.layoutSubtreeIfNeeded()
            scroll.tile()
            collection.needsLayout = true
            collection.layoutSubtreeIfNeeded()
            files.window?.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        collection.collectionViewLayout?.prepare()
    }

    private func fixture(count: Int) -> FilePinContent {
        FilePinContent(urls: (0..<count).map { URL(fileURLWithPath: "/tmp/pir-layout-\($0).txt") })
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let value = view as? T { return value }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }
}
