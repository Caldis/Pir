import AppKit
import Carbon
import PuvCore
import OSLog

final class GlobalHotKey: HotKeyBackend {
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 0
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var registeredKeys: [UInt32: HotKey] = [:]
    private var handlerStatus: OSStatus = noErr
    private let logger = Logger(subsystem: "me.caldis.puv", category: "hotkey")
    var onPress: (() -> Void)?
    var onPressWhileRecording: ((HotKey) -> Void)?
    var isRecording = false

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, owner.registrations[identifier.id] != nil else {
                return OSStatus(eventNotHandledErr)
            }
            if owner.isRecording {
                if let key = owner.registeredKeys[identifier.id] { owner.onPressWhileRecording?(key) }
            } else {
                owner.logger.info("Hotkey callback reached")
                owner.onPress?()
            }
            return noErr
        }, 1, &type, context, &handler)
    }

    func register(_ hotKey: HotKey) throws -> UInt32 {
        guard handlerStatus == noErr else {
            logger.error("Event handler installation failed status=\(self.handlerStatus, privacy: .public)")
            throw HotKeyError.registration(handlerStatus)
        }
        nextID &+= 1
        let identifier = EventHotKeyID(signature: 0x50555621, id: nextID)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(hotKey.keyCode), hotKey.carbonModifiers,
                                         identifier, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            logger.error("Hotkey registration failed status=\(status, privacy: .public)")
            throw HotKeyError.registration(status)
        }
        registrations[nextID] = reference
        registeredKeys[nextID] = hotKey
        return nextID
    }

    func unregister(_ token: UInt32) {
        guard let reference = registrations.removeValue(forKey: token) else { return }
        registeredKeys.removeValue(forKey: token)
        UnregisterEventHotKey(reference)
    }

    deinit {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
