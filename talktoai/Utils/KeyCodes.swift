//
//  KeyCodes.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import Carbon.HIToolbox

/// Common macOS key codes for hotkey detection
/// Reference: Carbon HIToolbox/Events.h
enum KeyCodes {
    // Modifier keys
    static let leftShift: UInt16 = UInt16(kVK_Shift)           // 56
    static let rightShift: UInt16 = UInt16(kVK_RightShift)     // 60
    static let leftControl: UInt16 = UInt16(kVK_Control)       // 59
    static let rightControl: UInt16 = UInt16(kVK_RightControl) // 62
    static let leftOption: UInt16 = UInt16(kVK_Option)         // 58
    static let rightOption: UInt16 = UInt16(kVK_RightOption)   // 61
    static let leftCommand: UInt16 = UInt16(kVK_Command)       // 55
    static let rightCommand: UInt16 = UInt16(kVK_RightCommand) // 54
    static let function: UInt16 = UInt16(kVK_Function)         // 63
    static let capsLock: UInt16 = UInt16(kVK_CapsLock)         // 57
    
    // Function keys
    static let f1: UInt16 = UInt16(kVK_F1)
    static let f2: UInt16 = UInt16(kVK_F2)
    static let f3: UInt16 = UInt16(kVK_F3)
    static let f4: UInt16 = UInt16(kVK_F4)
    static let f5: UInt16 = UInt16(kVK_F5)
    static let f6: UInt16 = UInt16(kVK_F6)
    static let f7: UInt16 = UInt16(kVK_F7)
    static let f8: UInt16 = UInt16(kVK_F8)
    static let f9: UInt16 = UInt16(kVK_F9)
    static let f10: UInt16 = UInt16(kVK_F10)
    static let f11: UInt16 = UInt16(kVK_F11)
    static let f12: UInt16 = UInt16(kVK_F12)
    
    // Common keys
    static let space: UInt16 = UInt16(kVK_Space)
    static let escape: UInt16 = UInt16(kVK_Escape)
    static let returnKey: UInt16 = UInt16(kVK_Return)
    static let tab: UInt16 = UInt16(kVK_Tab)
    static let delete: UInt16 = UInt16(kVK_Delete)

    // Letter keys
    static let keyK: UInt16 = UInt16(kVK_ANSI_K)  // 40
    
    /// Default push-to-talk key (Right Option)
    static let defaultPushToTalkKey: UInt16 = rightOption
    
    /// Check if a key code is a modifier key
    static func isModifier(_ keyCode: UInt16) -> Bool {
        let modifiers: Set<UInt16> = [
            leftShift, rightShift,
            leftControl, rightControl,
            leftOption, rightOption,
            leftCommand, rightCommand,
            function, capsLock
        ]
        return modifiers.contains(keyCode)
    }
    
    /// Human-readable name for a key code
    static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case leftShift: return "Left Shift"
        case rightShift: return "Right Shift"
        case leftControl: return "Left Control"
        case rightControl: return "Right Control"
        case leftOption: return "Left Option"
        case rightOption: return "Right Option"
        case leftCommand: return "Left Command"
        case rightCommand: return "Right Command"
        case function: return "Fn"
        case capsLock: return "Caps Lock"
        case f1: return "F1"
        case f2: return "F2"
        case f3: return "F3"
        case f4: return "F4"
        case f5: return "F5"
        case f6: return "F6"
        case f7: return "F7"
        case f8: return "F8"
        case f9: return "F9"
        case f10: return "F10"
        case f11: return "F11"
        case f12: return "F12"
        case space: return "Space"
        case escape: return "Escape"
        case returnKey: return "Return"
        case tab: return "Tab"
        case delete: return "Delete"
        default: return "Key \(keyCode)"
        }
    }
}
