import AppKit
import PirCore

enum PinFileSizing {
    static let iconSize: CGFloat = 56
    static let itemSize = NSSize(width: 88, height: 94)
    static let spacing: CGFloat = 8
    static let listRowHeight: CGFloat = 32

    static func columns(contentWidth: CGFloat) -> Int {
        max(1, Int(contentWidth / (itemSize.width + spacing)))
    }

    static func minimumSize(for layout: FilePinContent.Layout) -> NSSize {
        NSSize(width: 180, height: 58 + (layout == .icons ? itemSize.height : listRowHeight))
    }

    static func naturalSize(for content: FilePinContent, available: NSSize, width: CGFloat? = nil) -> NSSize {
        let minimum = minimumSize(for: content.layout)
        let preferredWidth = content.layout == .list ? 304 : CGFloat(min(3, max(1, content.urls.count))) * (itemSize.width + spacing) + 16
        let width = max(minimum.width, min(width ?? preferredWidth, available.width * 0.8))
        let columns = content.layout == .list ? 1 : columns(contentWidth: width - 16)
        let rows = max(1, (content.urls.count + columns - 1) / columns)
        let height = 58 + CGFloat(rows) * (content.layout == .icons ? itemSize.height : listRowHeight)
            + CGFloat(rows - 1) * (content.layout == .icons ? spacing : 4)
        return NSSize(width: width, height: max(minimum.height, min(height, 420, available.height * 0.6)))
    }
}
