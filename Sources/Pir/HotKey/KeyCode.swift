// Adapted from Caldis/Mos (752730c); Pir copy relicensed by Caldis under the repository LICENSE.
// Keyboard-only adaptation for Pir; see THIRD_PARTY_NOTICES.md.
import Cocoa

struct KeyCode {
    static let commandL: UInt16 = 55
    static let commandR: UInt16 = 54
    static let shiftL: UInt16 = 56
    static let shiftR: UInt16 = 60
    static let optionL: UInt16 = 58
    static let optionR: UInt16 = 61
    static let controlL: UInt16 = 59
    static let controlR: UInt16 = 62
    static let fnL: UInt16 = 63
    static let fnR: UInt16 = 179
    static let commandKeys: Set<UInt16> = [KeyCode.commandL, KeyCode.commandR]
    static let shiftKeys: Set<UInt16> = [KeyCode.shiftL, KeyCode.shiftR]
    static let optionKeys: Set<UInt16> = [KeyCode.optionL, KeyCode.optionR]
    static let controlKeys: Set<UInt16> = [KeyCode.controlL, KeyCode.controlR]
    static let fnKeys: Set<UInt16> = [KeyCode.fnL, KeyCode.fnR]
    static let modifierKeys: Set<UInt16> = [
        KeyCode.controlL,
        KeyCode.controlR,
        KeyCode.optionL,
        KeyCode.optionR,
        KeyCode.commandL,
        KeyCode.commandR,
        KeyCode.shiftL,
        KeyCode.shiftR,
        KeyCode.fnL,
        KeyCode.fnR
    ]
    static let modifierLKeys = [KeyCode.controlL, KeyCode.optionL, KeyCode.commandL, KeyCode.shiftL]
    static let modifierRKeys = [KeyCode.controlL, KeyCode.optionL, KeyCode.commandL, KeyCode.shiftL]
    static let modifiersMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskShift.rawValue
    static let keyCodeToMask: [UInt16: CGEventFlags] = [
        KeyCode.controlL: .maskControl,
        KeyCode.controlR: .maskControl,
        KeyCode.optionL: .maskAlternate,
        KeyCode.optionR: .maskAlternate,
        KeyCode.commandL: .maskCommand,
        KeyCode.commandR: .maskCommand,
        KeyCode.shiftL: .maskShift,
        KeyCode.shiftR: .maskShift,
        KeyCode.fnL: .maskSecondaryFn,
        KeyCode.fnR: .maskSecondaryFn,
    ]
    static func getKeyMask(_ keyCode: UInt16) -> CGEventFlags {
        return keyCodeToMask[keyCode] ?? CGEventFlags(rawValue: 0)
    }

    static let F1: UInt16 = 122
    static let F2: UInt16 = 120
    static let F3: UInt16 = 99
    static let F4: UInt16 = 118
    static let F5: UInt16 = 96
    static let F6: UInt16 = 97
    static let F7: UInt16 = 98
    static let F8: UInt16 = 100
    static let F9: UInt16 = 101
    static let F10: UInt16 = 109
    static let F11: UInt16 = 103
    static let F12: UInt16 = 111
    static let F13: UInt16 = 105
    static let F14: UInt16 = 107
    static let F15: UInt16 = 113
    static let F16: UInt16 = 106
    static let F17: UInt16 = 64
    static let F18: UInt16 = 79
    static let F19: UInt16 = 80
    static let F20: UInt16 = 90
    static let functionKeys: Set<UInt16> = [
        KeyCode.F1,
        KeyCode.F2,
        KeyCode.F3,
        KeyCode.F4,
        KeyCode.F5,
        KeyCode.F6,
        KeyCode.F7,
        KeyCode.F8,
        KeyCode.F9,
        KeyCode.F10,
        KeyCode.F11,
        KeyCode.F12,
        KeyCode.F13,
        KeyCode.F14,
        KeyCode.F15,
        KeyCode.F16,
        KeyCode.F17,
        KeyCode.F18,
        KeyCode.F19,
        KeyCode.F20
    ]

    static let arrowUp: UInt16 = 126
    static let arrowDown: UInt16 = 125
    static let arrowLeft: UInt16 = 123
    static let arrowRight: UInt16 = 124
    static let arrowKeys: Set<UInt16> = [
        KeyCode.arrowUp,
        KeyCode.arrowDown,
        KeyCode.arrowLeft,
        KeyCode.arrowRight
    ]

    static let escape: UInt16 = 53

    static let keyMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 26: "7", 28: "8", 29: "0", 25: "9",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        49: "⎵", 51: "⌫", 53: "⎋", 76: "↩", 36: "↩", 48: "↹", 57: "CapsLock",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        160: "F3 (MissionControl)",
        177: "F4 (Spotlight)",
        131: "F4 (AppExposé)",
        176: "F5 (Dictating)",
        178: "F6 (DND)",
        126: "↑", 125: "↓", 123: "←", 124: "→",
        116: "PageUp", 121: "PageDown", 115: "Home", 119: "End",
        63: "Fn", 59: "⌃", 58: "⌥", 55: "⌘", 56: "⇧",
        62: "⌃ (R)", 61: "⌥ (R)", 54: "⌘ (R)", 60: "⇧ (R)",
        179: "Fn (179)",
    ]

}
