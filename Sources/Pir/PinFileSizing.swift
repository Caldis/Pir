import AppKit
import PirCore

enum PinFileSizing {
    static let iconSize: CGFloat = 56
    static let itemSize = NSSize(width: 88, height: 94)
    static let spacing: CGFloat = 8
    static let listRowHeight: CGFloat = 32
    static let horizontalWindowInsets: CGFloat = 16
    static let verticalWindowInsets: CGFloat = 50
    static let contentInset: CGFloat = 4

    static func columns(contentWidth: CGFloat) -> Int {
        max(1, Int(contentWidth / (itemSize.width + spacing)))
    }

    static func minimumSize(for layout: FilePinContent.Layout) -> NSSize {
        NSSize(width: 180, height: verticalWindowInsets + contentInset * 2 + (layout == .icons ? itemSize.height : listRowHeight))
    }

    static func viewportSize(for scrollFrame: NSSize, style: NSScroller.Style, verticalScroller: Bool) -> NSSize {
        NSScrollView.contentSize(forFrameSize: scrollFrame, horizontalScrollerClass: nil,
                                 verticalScrollerClass: verticalScroller ? NSScroller.self : nil,
                                 borderType: .noBorder, controlSize: .regular, scrollerStyle: style)
    }

    private static func scrollFrameSize(for viewport: NSSize, style: NSScroller.Style, verticalScroller: Bool) -> NSSize {
        NSScrollView.frameSize(forContentSize: viewport, horizontalScrollerClass: nil,
                               verticalScrollerClass: verticalScroller ? NSScroller.self : nil,
                               borderType: .noBorder, controlSize: .regular, scrollerStyle: style)
    }

    static func documentHeight(count: Int, layout: FilePinContent.Layout, viewportWidth: CGFloat) -> CGFloat {
        let columns = layout == .list ? 1 : columns(contentWidth: viewportWidth)
        let rows = max(1, (count + columns - 1) / columns)
        return contentInset * 2 + CGFloat(rows) * (layout == .icons ? itemSize.height : listRowHeight)
            + CGFloat(rows - 1) * (layout == .icons ? spacing : 4)
    }

    static func layoutViewport(actual: NSSize, scrollFrame: NSSize, style: NSScroller.Style,
                               autohidesScrollers: Bool, count: Int, layout: FilePinContent.Layout) -> NSSize {
        let withoutScroller = viewportSize(for: scrollFrame, style: style, verticalScroller: false)
        // A stale legacy scroller can keep a wider, shorter layout trapped in an extra row.
        if autohidesScrollers, withoutScroller.width > actual.width + 0.5,
           documentHeight(count: count, layout: layout, viewportWidth: withoutScroller.width) <= withoutScroller.height {
            return withoutScroller
        }
        return actual
    }

    static func naturalSize(for content: FilePinContent, available: NSSize, width: CGFloat? = nil,
                            scrollerStyle: NSScroller.Style = NSScroller.preferredScrollerStyle) -> NSSize {
        let minimum = minimumSize(for: content.layout)
        let preferredViewportWidth = content.layout == .list ? 288 : CGFloat(min(3, max(1, content.urls.count))) * (itemSize.width + spacing)
        let preferredWidth = preferredViewportWidth + horizontalWindowInsets
        let maximumHeight = max(minimum.height, min(420, available.height * 0.6))
        var resolvedWidth = max(minimum.width, min(width ?? preferredWidth, available.width * 0.8))
        let noScroller = viewportSize(for: NSSize(width: resolvedWidth - horizontalWindowInsets,
                                                 height: maximumHeight - verticalWindowInsets),
                                      style: scrollerStyle, verticalScroller: false)
        let needsScrolling = documentHeight(count: content.urls.count, layout: content.layout, viewportWidth: noScroller.width) > noScroller.height
        if width == nil, needsScrolling {
            let preferredFrame = scrollFrameSize(for: NSSize(width: preferredViewportWidth, height: noScroller.height),
                                                 style: scrollerStyle, verticalScroller: true)
            resolvedWidth = max(minimum.width, min(preferredFrame.width + horizontalWindowInsets, available.width * 0.8))
        }
        let viewport = viewportSize(for: NSSize(width: resolvedWidth - horizontalWindowInsets,
                                                height: maximumHeight - verticalWindowInsets),
                                     style: scrollerStyle, verticalScroller: needsScrolling)
        let height = verticalWindowInsets + documentHeight(count: content.urls.count, layout: content.layout, viewportWidth: viewport.width)
        return NSSize(width: resolvedWidth, height: max(minimum.height, min(height, maximumHeight)))
    }
}
