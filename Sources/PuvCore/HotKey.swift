import AppKit
import Carbon

public struct HotKey: Codable, Equatable {
    public let keyCode: UInt16
    public let modifierBits: UInt
    public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }
    public static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    public static let `default` = HotKey(keyCode: 9, modifiers: [.command, .option])

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifierBits = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    public var isValid: Bool {
        let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 179]
        let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                       105, 107, 113, 106, 64, 79, 80, 90]
        return keyCode <= 126 && keyCode != 53 && !modifierKeys.contains(keyCode)
            && (modifierBits != 0 || functionKeys.contains(keyCode))
            && modifierBits & ~Self.supportedModifiers.rawValue == 0
    }

    public var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    // Mos uses the same badge ordering while recording and displaying a saved key.
    public var modifierSymbols: String {
        var symbols: [String] = []
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        return symbols.joined(separator: " ")
    }
}

public protocol HotKeyBackend: AnyObject {
    associatedtype Token
    func register(_ hotKey: HotKey) throws -> Token
    func unregister(_ token: Token)
}

public enum HotKeyError: Error { case invalid, registration(OSStatus) }

public final class HotKeyBinding<Backend: HotKeyBackend> {
    private let backend: Backend
    private var token: Backend.Token?
    public private(set) var current: HotKey?

    public init(backend: Backend) { self.backend = backend }

    public func replace(with hotKey: HotKey) throws {
        guard hotKey.isValid else { throw HotKeyError.invalid }
        guard current != hotKey else { return }
        // Register first: a conflict leaves the existing working shortcut intact.
        let replacement = try backend.register(hotKey)
        if let token { backend.unregister(token) }
        token = replacement
        current = hotKey
    }

    public func clear() {
        if let token { backend.unregister(token) }
        token = nil
        current = nil
    }

    deinit { clear() }
}
