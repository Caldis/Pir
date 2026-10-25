// Adapted from Mos/Keys/KeyRecorder.swift (752730c); Puv copy relicensed by Caldis under the repository LICENSE.
// Puv retains combination recording, feedback and cancellation; see THIRD_PARTY_NOTICES.md.
import AppKit
import PuvCore

final class KeyRecorder {
    static let timeout: TimeInterval = 10
    private var monitor: Any?
    private var timer: Timer?
    private var popover: KeyPopover?
    private var recorded = false
    private var observers: [NSObjectProtocol] = []
    var onRecord: ((HotKey) throws -> Void)?
    var currentHotKey: (() -> HotKey?)?
    var onStateChange: ((Bool) -> Void)?

    func start(from source: NSView) {
        stop()
        recorded = false
        let popover = KeyPopover()
        self.popover = popover
        popover.onClose = { [weak self] in self?.stop() }
        popover.show(at: source)
        popover.showEscHint()
        onStateChange?(true)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                 object: NSApp, queue: .main) { [weak self] _ in self?.stop() })
        if let window = source.window {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                     object: window, queue: .main) { [weak self] _ in self?.stop() })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let consumed = self.handle(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                       isFlagsChange: event.type == .flagsChanged)
            return consumed ? nil : event
        }
        refreshTimeout()
    }

    private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isFlagsChange: Bool) -> Bool {
        guard !recorded else { return false }
        if isFlagsChange {
            popover?.keyPreview.updateForRecording(modifiers: CGEventFlags(rawValue: UInt64(modifiers.rawValue)))
            refreshTimeout()
            return false
        }
        if keyCode == KeyCode.escape {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return true
        }
        let shortcut = HotKey(keyCode: keyCode, modifiers: modifiers)
        guard shortcut.isValid else {
            popover?.keyPreview.shakeWarning()
            return true
        }
        do {
            let unchanged = currentHotKey?() == shortcut
            try onRecord?(shortcut)
            recorded = true
            timer?.invalidate()
            popover?.keyPreview.update(from: shortcut.displayComponents, status: unchanged ? .unchanged : .recorded)
            popover?.showEscHint()
            timer = Timer.scheduledTimer(withTimeInterval: unchanged ? 1 : 0.7, repeats: false) { [weak self] _ in self?.stop() }
        } catch {
            popover?.keyPreview.update(from: shortcut.displayComponents, status: .duplicate)
            popover?.showDuplicateHint()
            refreshTimeout()
        }
        return true
    }

    func recordRegisteredHotKey(_ key: HotKey) {
        // Carbon consumes registered combinations before the local NSEvent monitor sees keyDown.
        guard popover != nil else { return }
        _ = handle(keyCode: key.keyCode, modifiers: key.modifiers, isFlagsChange: false)
    }

    func stop() {
        let wasRecording = monitor != nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        let oldPopover = popover
        popover = nil
        oldPopover?.onClose = nil
        oldPopover?.hide()
        if wasRecording { onStateChange?(false) }
    }

    private func refreshTimeout() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.timeout, repeats: false) { [weak self] _ in self?.stop() }
    }

    deinit { stop() }
}

extension HotKey {
    var displayComponents: [String] {
        let name = KeyCode.keyMap[keyCode] ?? "Key \(keyCode)"
        return modifierSymbols.isEmpty ? [name] : [modifierSymbols, name]
    }
}
