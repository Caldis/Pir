// Adapted from Caldis/Mos (752730c); Pir copy relicensed by Caldis under the repository LICENSE.
// Keyboard-only adaptation for Pir; see THIRD_PARTY_NOTICES.md.
import Cocoa

class KeyPreview: NSStackView {

    static let VIEW_SIZE = CGFloat(25)
    static let FONT_SIZE = CGFloat(11)
    static let WAITING_WORDING = "?"

    enum Status {
        case normal
        case recorded
        case unchanged
        case duplicate
        case recording
    }

    private var keyComponents: [String] = []
    private var status: Status = .normal
    private var keyViews: [NSView] = []
    private var waitingView: KeyComponentContainer?
    private var keycapSize = KeyPreview.VIEW_SIZE
    private var fontSize = KeyPreview.FONT_SIZE

    convenience init(keycapSize: CGFloat, fontSize: CGFloat = KeyPreview.FONT_SIZE) {
        self.init(frame: .zero)
        self.keycapSize = keycapSize
        self.fontSize = fontSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    private func setupView() {
        wantsLayer = true

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        update(from: [KeyPreview.WAITING_WORDING], status: .recording)
    }


    func update(from components: [String], status: Status = .normal) {
        self.keyComponents = components
        self.status = status

        clearKeyViews()

        guard !components.isEmpty else { return }

        createKeyViews()
    }

    func updateForRecording(modifiers flags: CGEventFlags) {
        var components: [String] = []
        if flags.contains(.maskShift) { components.append("⇧") }
        if flags.contains(.maskSecondaryFn) { components.append("Fn") }
        if flags.contains(.maskControl) { components.append("⌃") }
        if flags.contains(.maskAlternate) { components.append("⌥") }
        if flags.contains(.maskCommand) { components.append("⌘") }
        let modString = components.joined(separator: " ")
        if !modString.isEmpty {
            update(from: [modString, KeyPreview.WAITING_WORDING], status: .recording)
        } else {
            update(from: [KeyPreview.WAITING_WORDING], status: .recording)
        }
    }

    func shakeWarning() {
        waitingView?.shakeWarning()
    }

    private func clearKeyViews() {
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyViews.removeAll()
        waitingView = nil
    }
    private func createKeyViews() {
        for (index, component) in keyComponents.enumerated() {
            if index > 0 {
                let plusLabel = NSTextField(labelWithString: "+")
                plusLabel.font = NSFont.systemFont(ofSize: fontSize)
                plusLabel.textColor = .secondaryLabelColor
                addArrangedSubview(plusLabel)
            }
            let isWaiting = component == Self.WAITING_WORDING
            let keyView = createSingleKeyView(for: component, isWaiting: isWaiting)
            addArrangedSubview(keyView)
            keyViews.append(keyView)
            if isWaiting { waitingView = keyView as? KeyComponentContainer }
        }
    }
    private func createSingleKeyView(for text: String, isWaiting: Bool) -> NSView {
        let container = KeyComponentContainer(keyStatus: status, isWaiting: isWaiting)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        label.textColor = [.recorded, .unchanged, .duplicate].contains(status) ? NSColor.white : NSColor.labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: max(keycapSize, ceil(label.intrinsicContentSize.width) + 12)),
            container.heightAnchor.constraint(equalToConstant: keycapSize),
        ])

        return container
    }
}

private final class KeyComponentContainer: NSView {
    override var wantsUpdateLayer: Bool { true }
    let keyStatus: KeyPreview.Status
    let isWaitingPlaceholder: Bool

    init(keyStatus: KeyPreview.Status, isWaiting: Bool = false) {
        self.keyStatus = keyStatus
        self.isWaitingPlaceholder = isWaiting
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4

        if keyStatus == .recording && isWaitingPlaceholder {
            startBreathingAnimation()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = getBackgroundColor().cgColor
    }

    private func getBackgroundColor() -> NSColor {
        switch keyStatus {
        case .normal, .recording:
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return dark ? NSColor(calibratedWhite: 0.5, alpha: 0.2) : NSColor(calibratedWhite: 0, alpha: 0.1)
        case .recorded:
            return NSColor.systemGreen
        case .unchanged:
            return NSColor.systemBlue
        case .duplicate:
            return NSColor.systemRed
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func startBreathingAnimation() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.5
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(animation, forKey: "breathingAnimation")
    }

    func shakeWarning() {
        guard let layer = layer else { return }

        layer.removeAnimation(forKey: "breathingAnimation")
        layer.opacity = 1.0

        let shakeAnimation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shakeAnimation.values = [0, -8, 8, -8, 8, -4, 4, 0]
        shakeAnimation.duration = 0.4
        shakeAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let warningColor: CGColor = NSColor.systemRed.cgColor
        let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
        colorAnimation.fromValue = warningColor
        colorAnimation.toValue = layer.backgroundColor
        colorAnimation.duration = 0.8
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        layer.add(shakeAnimation, forKey: "shakeWarning")
        layer.add(colorAnimation, forKey: "colorWarning")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.keyStatus == .recording {
                self.startBreathingAnimation()
            }
        }
    }
}
