import Foundation

public struct ResizeEdges: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = Self(rawValue: 1)
    public static let right = Self(rawValue: 2)
    public static let top = Self(rawValue: 4)
    public static let bottom = Self(rawValue: 8)
}

public enum PinGeometry {
    public static let minimumSize = CGSize(width: 120, height: 80)

    public static func initialSize(content: CGSize, available: CGSize, minimum: CGSize = minimumSize) -> CGSize {
        guard content.width > 0, content.height > 0 else { return minimum }
        let scale = min(1, available.width * 0.8 / content.width, available.height * 0.8 / content.height)
        return CGSize(width: max(minimum.width, content.width * scale),
                      height: max(minimum.height, content.height * scale))
    }

    public static func resize(frame: CGRect, delta: CGPoint, edges: ResizeEdges, minimum: CGSize = minimumSize) -> CGRect {
        var result = frame
        if edges.contains(.left) {
            result.size.width = max(minimum.width, frame.width - delta.x)
            result.origin.x = frame.maxX - result.width
        } else if edges.contains(.right) {
            result.size.width = max(minimum.width, frame.width + delta.x)
        }
        if edges.contains(.bottom) {
            result.size.height = max(minimum.height, frame.height - delta.y)
            result.origin.y = frame.maxY - result.height
        } else if edges.contains(.top) {
            result.size.height = max(minimum.height, frame.height + delta.y)
        }
        return result
    }
}
