import Foundation
import Carbon
import AppKit

/// 键盘快捷键数据模型与 Zero-Permission 键码映射器
public struct HotKeyShortcut: Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var displayString: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayString = displayString
    }

    public static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(optionKey),
        displayString: "⌥S"
    )

    /// 将 NSEvent 的 keyCode 和 modifierFlags 转化为 HotKeyShortcut
    public static func from(event: NSEvent) -> HotKeyShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // 必须至少包含一个有效修饰键 (Command, Option, Control, Shift)
        var carbonMods: UInt32 = 0
        var modString = ""

        if flags.contains(.control) {
            carbonMods |= UInt32(controlKey)
            modString += "⌃"
        }
        if flags.contains(.option) {
            carbonMods |= UInt32(optionKey)
            modString += "⌥"
        }
        if flags.contains(.shift) {
            carbonMods |= UInt32(shiftKey)
            modString += "⇧"
        }
        if flags.contains(.command) {
            carbonMods |= UInt32(cmdKey)
            modString += "⌘"
        }

        // 如果没有修饰键，或者只按了修饰键本身，不构成有效快捷键
        guard carbonMods != 0 else { return nil }

        let kCode = UInt32(event.keyCode)
        guard let keyName = stringForKeyCode(kCode) else { return nil }

        return HotKeyShortcut(
            keyCode: kCode,
            carbonModifiers: carbonMods,
            displayString: "\(modString)\(keyName)"
        )
    }

    /// 常用 macOS 物理按键键码字符转换表
    public static func stringForKeyCode(_ keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"

        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"

        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        default:
            return nil
        }
    }
}
