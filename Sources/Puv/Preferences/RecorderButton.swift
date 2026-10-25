import AppKit
import PuvCore

final class RecorderButton: NSButton {
    enum Style { case preferences, onboarding }
    private let recorder = KeyRecorder()
    private let model: PreferencesModel
    private let preview: KeyPreview
    private let style: Style
    private let placeholder = NSTextField(labelWithString: L("Click to record"))

    init(model: PreferencesModel, style: Style = .preferences, onRecorded: (() -> Void)? = nil) {
        self.model = model
        self.style = style
        preview = KeyPreview(keycapSize: style == .onboarding ? 32 : 20,
                             fontSize: style == .onboarding ? 16 : KeyPreview.FONT_SIZE)
        super.init(frame: .zero)
        bezelStyle = .regularSquare
        alignment = .left
        font = PreferencesStyle.controlFont
        target = self
        action = #selector(record)
        setAccessibilityLabel(L("Record paste shortcut"))
        toolTip = L("Click, then press a key combination. Escape cancels.")
        preview.setHuggingPriority(.required, for: .horizontal)
        preview.setContentHuggingPriority(.required, for: .horizontal)
        placeholder.font = PreferencesStyle.controlFont
        placeholder.textColor = .secondaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        addSubview(placeholder)
        if style == .onboarding {
            isBordered = false
            wantsLayer = true
            layer?.cornerRadius = 10
            layer?.borderWidth = 1
            updateOutline()
            preview.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            preview.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8).isActive = true
        } else {
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
        }
        NSLayoutConstraint.activate([
            preview.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: style == .onboarding ? -8 : -4),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        recorder.currentHotKey = { [weak model] in
            guard let model, model.hotKeyEnabled else { return nil }
            return model.hotKey
        }
        recorder.onRecord = { [weak model] value in
            guard let model else { return }
            try model.setHotKey(value)
            onRecorded?()
        }
        recorder.onStateChange = { [weak model] active in model?.onRecordingChange?(active) }
        update(model.hotKey, enabled: model.hotKeyEnabled)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func update(_ value: HotKey, enabled: Bool) {
        title = ""
        preview.isHidden = !enabled
        placeholder.isHidden = enabled
        if enabled { preview.update(from: value.displayComponents) }
        setAccessibilityValue(enabled ? value.displayComponents.joined(separator: " + ") : L("Not set"))
    }
    @objc private func record() {
        model.onHotKeyDuringRecording = { [weak recorder] key in recorder?.recordRegisteredHotKey(key) }
        recorder.start(from: self)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOutline()
    }
    private func updateOutline() {
        guard style == .onboarding else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { recorder.stop() }
    }
}
