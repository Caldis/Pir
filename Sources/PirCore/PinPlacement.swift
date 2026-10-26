import Foundation

public struct PinDisplay: Equatable {
    public let id: String
    public let visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }

    public static func best(for frame: CGRect, among displays: [PinDisplay]) -> PinDisplay? {
        displays.max { left, right in
            let a = left.visibleFrame.intersection(frame)
            let b = right.visibleFrame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
    }
}

public struct PinPlacement {
    public let displayID: String
    public let frame: CGRect
    public let isFallback: Bool
}

public struct PinAnchor: Codable, Equatable {
    public let displayID: String
    public private(set) var size: CGSize
    public let horizontalFraction: Double
    public let verticalFraction: Double

    public init(frame: CGRect, display: PinDisplay) {
        displayID = display.id
        size = frame.size
        horizontalFraction = Self.fraction(frame.minX - display.visibleFrame.minX, travel: display.visibleFrame.width - frame.width)
        verticalFraction = Self.fraction(frame.minY - display.visibleFrame.minY, travel: display.visibleFrame.height - frame.height)
    }

    public func updatedByUser(frame: CGRect, previousFrame: CGRect, displays: [PinDisplay]) -> PinAnchor {
        guard frame != previousFrame else { return self }
        if frame.size != previousFrame.size {
            if let preferred = displays.first(where: { $0.id == displayID }) { return PinAnchor(frame: frame, display: preferred) }
            // Resizing a temporary fallback changes dimensions while retaining its disconnected home display.
            var updated = self
            updated.size = frame.size
            return updated
        }
        guard let target = PinDisplay.best(for: frame, among: displays) else { return self }
        return PinAnchor(frame: frame, display: target)
    }

    public var isValid: Bool {
        !displayID.isEmpty && size.width.isFinite && size.height.isFinite &&
        size.width > 0 && size.height > 0 && horizontalFraction.isFinite && verticalFraction.isFinite &&
        (0...1).contains(horizontalFraction) && (0...1).contains(verticalFraction)
    }

    public func resolve(displays: [PinDisplay], fallbackDisplayID: String?, minimum: CGSize = PinGeometry.minimumSize) -> PinPlacement? {
        guard isValid else { return nil }
        let preferred = displays.first { $0.id == displayID }
        guard let display = preferred ?? displays.first(where: { $0.id == fallbackDisplayID }) ?? displays.first else { return nil }
        let visible = display.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return nil }
        let width = min(visible.width, max(minimum.width, size.width))
        let height = min(visible.height, max(minimum.height, size.height))
        let frame = CGRect(x: visible.minX + max(0, visible.width - width) * horizontalFraction,
                           y: visible.minY + max(0, visible.height - height) * verticalFraction,
                           width: width, height: height)
        return PinPlacement(displayID: display.id, frame: frame, isFallback: preferred == nil)
    }

    private static func fraction(_ value: CGFloat, travel: CGFloat) -> Double {
        guard value.isFinite, travel.isFinite, travel > 0 else { return 0 }
        return Double(min(1, max(0, value / travel)))
    }
}
