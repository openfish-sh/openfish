import Carbon.HIToolbox
import AppKit
import CoreGraphics

/// A specific physical modifier key. Distinguishes left/right by virtual keycode,
/// which a CGEventTap exposes on `flagsChanged` (the shared modifier flag does not).
enum ModifierKey: String, CaseIterable {
    case leftOption, rightOption
    case leftCommand, rightCommand
    case leftControl, rightControl
    case leftShift, rightShift
    case fn

    var keyCode: UInt16 {
        switch self {
        case .leftOption: return UInt16(kVK_Option)
        case .rightOption: return UInt16(kVK_RightOption)
        case .leftCommand: return UInt16(kVK_Command)
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .leftControl: return UInt16(kVK_Control)
        case .rightControl: return UInt16(kVK_RightControl)
        case .leftShift: return UInt16(kVK_Shift)
        case .rightShift: return UInt16(kVK_RightShift)
        case .fn: return UInt16(kVK_Function)
        }
    }

    var displayName: String {
        switch self {
        case .leftOption: return "Left ⌥"
        case .rightOption: return "Right ⌥"
        case .leftCommand: return "Left ⌘"
        case .rightCommand: return "Right ⌘"
        case .leftControl: return "Left ⌃"
        case .rightControl: return "Right ⌃"
        case .leftShift: return "Left ⇧"
        case .rightShift: return "Right ⇧"
        case .fn: return "Fn"
        }
    }

    /// The CGEvent modifier flag this key sets (left/right share a flag — keycode
    /// distinguishes them). Used to read live modifier state from the event itself.
    var cgFlagMask: CGEventFlags {
        switch self {
        case .leftOption, .rightOption: return .maskAlternate
        case .leftCommand, .rightCommand: return .maskCommand
        case .leftControl, .rightControl: return .maskControl
        case .leftShift, .rightShift: return .maskShift
        case .fn: return .maskSecondaryFn
        }
    }

    var isFn: Bool { self == .fn }
}

/// How a hotkey fires:
/// - `chord`: a key + modifiers pressed together (fires on key-down).
/// - `modifierTap`: a single modifier key tapped on its own (fires on release,
///   only if no other key/modifier was involved — so ⌥e for accents won't trigger).
/// - `modifierHold`: a single modifier held down (start on press, stop on release) —
///   used for hold-to-talk.
enum HotkeyTrigger: Equatable {
    case chord(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)
    case modifierTap(ModifierKey)
    case modifierHold(ModifierKey)

    /// Default trigger for generating a reply: tap the **Right Option** key.
    static let defaultGenerate: HotkeyTrigger = .modifierTap(.rightOption)
    /// Default dictation trigger: **hold Fn** to talk, release to stop.
    static let defaultDictate: HotkeyTrigger = .modifierHold(.fn)

    var displayString: String {
        switch self {
        case .chord(let keyCode, let mods):
            return Self.chordString(keyCode: keyCode, mods: mods)
        case .modifierTap(let key):
            return "\(key.displayName) (tap)"
        case .modifierHold(let key):
            return "\(key.displayName) (hold)"
        }
    }

    // MARK: UserDefaults string encoding

    var encoded: String {
        switch self {
        case .chord(let keyCode, let mods): return "chord:\(keyCode):\(mods.rawValue)"
        case .modifierTap(let key): return "tap:\(key.rawValue)"
        case .modifierHold(let key): return "hold:\(key.rawValue)"
        }
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 2).map(String.init)
        guard let kind = parts.first else { return nil }
        switch kind {
        case "tap":
            guard parts.count == 2, let key = ModifierKey(rawValue: parts[1]) else { return nil }
            self = .modifierTap(key)
        case "hold":
            guard parts.count == 2, let key = ModifierKey(rawValue: parts[1]) else { return nil }
            self = .modifierHold(key)
        case "chord":
            guard parts.count == 3, let kc = UInt16(parts[1]), let raw = UInt(parts[2]) else { return nil }
            self = .chord(keyCode: kc, modifiers: NSEvent.ModifierFlags(rawValue: raw))
        default:
            return nil
        }
    }

    // MARK: Chord display helper

    private static func chordString(keyCode: UInt16, mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        default: return "Key\(keyCode)"
        }
    }
}
