import AppKit
import Carbon
import XCTest
import PuvCore
@testable import Puv

final class GlobalHotKeyTests: XCTestCase {
    @MainActor
    func testRecordingCurrentShortcutShowsBlueFeedback() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 150),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let source = NSButton(frame: NSRect(x: 40, y: 50, width: 120, height: 24))
        window.contentView?.addSubview(source)
        window.makeKeyAndOrderFront(nil)
        let recorder = KeyRecorder()
        defer { recorder.stop(); window.close() }
        recorder.currentHotKey = { .default }
        var recorded: [HotKey] = []
        recorder.onRecord = { recorded.append($0) }
        recorder.start(from: source)
        recorder.recordRegisteredHotKey(.default)
        XCTAssertEqual(recorded, [.default])
        let preview = try XCTUnwrap(NSApp.windows.compactMap { findPreview(in: $0.contentView) }.first)
        preview.window?.displayIfNeeded()
        let key = try XCTUnwrap(preview.arrangedSubviews.first)
        key.displayIfNeeded()
        let color = try XCTUnwrap(key.layer?.backgroundColor)
        key.effectiveAppearance.performAsCurrentDrawingAppearance {
            XCTAssertEqual(color, NSColor.systemBlue.cgColor)
        }
        recorder.recordRegisteredHotKey(.default)
        XCTAssertEqual(recorded, [.default], "The feedback interval consumes repeated activation")
    }

    private func findPreview(in view: NSView?) -> KeyPreview? {
        guard let view else { return nil }
        if let preview = view as? KeyPreview { return preview }
        return view.subviews.lazy.compactMap { self.findPreview(in: $0) }.first
    }

    func testRegisteredCarbonEventDispatchAndRecordingSuppression() throws {
        _ = NSApplication.shared
        let backend = GlobalHotKey()
        let key = HotKey(keyCode: 80, modifiers: [.command, .option, .control, .shift])
        let token = try backend.register(key)
        defer { backend.unregister(token) }
        var presses = 0
        backend.onPress = { presses += 1 }

        try dispatchHotKey(token: token)
        XCTAssertEqual(presses, 1)
        backend.isRecording = true
        var captured: [HotKey] = []
        backend.onPressWhileRecording = { captured.append($0) }
        try dispatchHotKey(token: token)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(captured, [key])
        backend.isRecording = false
        try dispatchHotKey(token: token)
        XCTAssertEqual(presses, 2)
        XCTAssertEqual(captured, [key])
    }

    private func dispatchHotKey(token: UInt32) throws {
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                  GetCurrentEventTime(), 0, &event)
        XCTAssertEqual(created, noErr)
        let value = try XCTUnwrap(event)
        defer { ReleaseEvent(value) }
        var identifier = EventHotKeyID(signature: 0x50555621, id: token)
        let parameter = SetEventParameter(value, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           MemoryLayout<EventHotKeyID>.size, &identifier)
        XCTAssertEqual(parameter, noErr)
        XCTAssertEqual(SendEventToEventTarget(value, GetApplicationEventTarget()), noErr)
    }
}
