// Adapted from Mos/Keys/KeyRecorder.swift (752730c); Puv copy relicensed by Caldis under the repository LICENSE.
// Puv retains combination recording, feedback and cancellation; see THIRD_PARTY_NOTICES.md.
import AppKit
import ApplicationServices
import PuvCore

final class KeyRecorder {
    static let timeout: TimeInterval = 10
    private var monitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var popover: KeyPopover?
    private var recorded = false
    private var observers: [NSObjectProtocol] = []
    var onRecord: ((HotKey) throws -> Void)?
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
        if !startGlobalCaptureIfAuthorized() {
            // Local capture remains available when the optional Accessibility grant is absent.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                let consumed = self.handle(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                           isFlagsChange: event.type == .flagsChanged)
                return consumed ? nil : event
            }
        }
        refreshTimeout()
    }

    private func startGlobalCaptureIfAuthorized() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<KeyRecorder>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = recorder.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let consumed = recorder.handle(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                            modifiers: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)),
                                            isFlagsChange: type == .flagsChanged)
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        eventTap = tap
        runLoopSource = source
        // The tap shares the main run loop with AppKit; no callback races with recording teardown.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isFlagsChange: Bool) -> Bool {
        guard !recorded else { return false }
        if isFlagsChange {
            popover?.keyPreview.updateForRecording(modifiers: CGEventFlags(rawValue: UInt64(modifiers.rawValue)))
            refreshTimeout()
            return false
        }
        if keyCode == KeyCode.escape {
            // Event-tap teardown occurs after the current callback has returned to CoreGraphics.
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return true
        }
        let shortcut = HotKey(keyCode: keyCode, modifiers: modifiers)
        guard shortcut.isValid else {
            popover?.keyPreview.shakeWarning()
            return true
        }
        do {
            try onRecord?(shortcut)
            recorded = true
            timer?.invalidate()
            popover?.keyPreview.update(from: shortcut.displayComponents, status: .recorded)
            timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in self?.stop() }
        } catch {
            popover?.keyPreview.update(from: shortcut.displayComponents, status: .duplicate)
            popover?.showDuplicateHint()
            refreshTimeout()
        }
        return true
    }

    func stop() {
        let wasRecording = monitor != nil || eventTap != nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
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
