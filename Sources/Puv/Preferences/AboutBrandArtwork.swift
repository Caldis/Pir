import AppKit
import QuartzCore

/// A monochrome rendering of Puv's two glass sheets behind the About title.
@MainActor
final class AboutBrandArtwork: NSView {
    private enum Style {
        static let aspectRatio: CGFloat = 1.28
        static let driftDuration: CFTimeInterval = 16
        static let reflectionDuration: CFTimeInterval = 11
        static let driftAngle: CGFloat = 0.018
    }

    private let sheets = CALayer()
    private let rear = CAShapeLayer()
    private let front = CAShapeLayer()
    private let reflection = CALayer()
    private let reflectionMask = CAShapeLayer()
    private let reflectionGradient = CAGradientLayer()
    private let visibilityMask = CAGradientLayer()
    private var presentationActive = true
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        visibilityMask.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        visibilityMask.locations = [0, 0.25, 0.85, 1]
        visibilityMask.startPoint = CGPoint(x: 0.5, y: 0)
        visibilityMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.mask = visibilityMask
        setAccessibilityElement(false)
        layer?.addSublayer(sheets)
        sheets.addSublayer(rear)
        sheets.addSublayer(front)
        sheets.addSublayer(reflection)
        reflection.mask = reflectionMask
        reflection.addSublayer(reflectionGradient)
        reflectionGradient.startPoint = CGPoint(x: 0, y: 0.1)
        reflectionGradient.endPoint = CGPoint(x: 1, y: 0.9)
        reflectionGradient.locations = [0, 0.45, 0.5, 0.55, 1]
        for sheet in [rear, front] {
            sheet.lineJoin = .round
            sheet.lineWidth = 0.7
        }

        let center = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,
                     NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(windowStateChanged(_:)), name: name, object: nil)
        }
        for name in [NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            center.addObserver(self, selector: #selector(displayOptionsChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Tab controllers call this when their page enters or leaves presentation.
    func setPresentationActive(_ active: Bool) {
        presentationActive = active
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateAnimation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func layout() {
        super.layout()
        let width = bounds.width * 0.8
        let height = width / Style.aspectRatio
        let size = CGSize(width: width, height: height)
        let localBounds = CGRect(origin: .zero, size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        visibilityMask.frame = bounds
        sheets.frame = CGRect(x: -width * 0.28, y: -height * 0.3,
                              width: width, height: height)
        for sheet in [rear, front] { sheet.frame = localBounds }
        let backPath = Self.roundedSheet([
            CGPoint(x: 0.44, y: 0.98), CGPoint(x: 0.94, y: 0.82),
            CGPoint(x: 0.94, y: 0.34), CGPoint(x: 0.44, y: 0.51)
        ], size: size)
        let frontPath = Self.roundedSheet([
            CGPoint(x: 0.08, y: 0.76), CGPoint(x: 0.68, y: 0.54),
            CGPoint(x: 0.68, y: 0.02), CGPoint(x: 0.08, y: 0.25)
        ], size: size)
        rear.path = backPath
        front.path = frontPath
        reflection.frame = localBounds
        reflectionMask.frame = localBounds
        let maskPath = CGMutablePath()
        maskPath.addPath(backPath)
        maskPath.addPath(frontPath)
        reflectionMask.path = maskPath
        reflectionGradient.frame = localBounds.insetBy(dx: -width, dy: -height / 2)
        CATransaction.commit()
        updateAnimation()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let ink = NSColor.labelColor
            let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rear.fillColor = ink.withAlphaComponent(increasedContrast ? 0.10 : 0.025).cgColor
            front.fillColor = ink.withAlphaComponent(increasedContrast ? 0.13 : 0.04).cgColor
            for sheet in [rear, front] {
                sheet.strokeColor = ink.withAlphaComponent(increasedContrast ? 0.30 : 0.17).cgColor
            }
            let clear = ink.withAlphaComponent(0).cgColor
            reflectionGradient.colors = [clear, clear, ink.withAlphaComponent(0.05).cgColor, clear, clear]
            CATransaction.commit()
        }
    }

    @objc private func displayOptionsChanged() {
        updateColors()
        updateAnimation()
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        guard let affectedWindow = notification.object as? NSWindow, affectedWindow === window else { return }
        if notification.name == NSWindow.willCloseNotification {
            stopAnimation()
        } else {
            updateAnimation()
        }
    }

    private func updateAnimation() {
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false
        let shouldAnimate = presentationActive && visible && !isHiddenOrHasHiddenAncestor && NSApp.isActive
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !bounds.isEmpty
        guard shouldAnimate else {
            stopAnimation()
            return
        }
        guard !isAnimating else { return }
        isAnimating = true

        let drift = CABasicAnimation(keyPath: "transform.rotation.z")
        drift.fromValue = -Style.driftAngle
        drift.toValue = Style.driftAngle
        drift.duration = Style.driftDuration
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sheets.add(drift, forKey: "sheetDrift")

        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        sweep.fromValue = -bounds.width
        sweep.toValue = bounds.width
        sweep.duration = Style.reflectionDuration
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        reflectionGradient.add(sweep, forKey: "reflectionSweep")
    }

    private func stopAnimation() {
        sheets.removeAllAnimations()
        reflectionGradient.removeAllAnimations()
        isAnimating = false
    }

    private static func roundedSheet(_ points: [CGPoint], size: CGSize) -> CGPath {
        let vertices = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let path = CGMutablePath()
        let rounding: CGFloat = 0.11
        for index in vertices.indices {
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let vertex = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            let entry = CGPoint(x: vertex.x + (previous.x - vertex.x) * rounding,
                                y: vertex.y + (previous.y - vertex.y) * rounding)
            let exit = CGPoint(x: vertex.x + (next.x - vertex.x) * rounding,
                               y: vertex.y + (next.y - vertex.y) * rounding)
            if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: exit, control: vertex)
        }
        path.closeSubpath()
        return path
    }
}
