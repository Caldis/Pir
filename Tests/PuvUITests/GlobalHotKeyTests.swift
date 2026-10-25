import AppKit
import Carbon
import XCTest
import PuvCore
@testable import Puv

final class GlobalHotKeyTests: XCTestCase {
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
        try dispatchHotKey(token: token)
        XCTAssertEqual(presses, 1)
        backend.isRecording = false
        try dispatchHotKey(token: token)
        XCTAssertEqual(presses, 2)
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
