import Foundation

/// A key pressed with modifiers: the key by its hardware key code, which is the same on every
/// keyboard layout, and the modifiers held with it. `character` is what the key typed when it was
/// recorded, kept only to write the combination out ("⌃⌥P").
public struct KeyCombo: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// All four at once: what the Hyper key holds.
        public static let hyper: Modifiers = [.control, .option, .shift, .command]
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: Modifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }

    /// The same keys are the same combination, whatever they typed when recorded.
    public static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    /// Whether it can be a trigger: it needs ⌘, ⌃ or ⌥, or a function key, so it never eats what you type.
    public var isUsableAsTrigger: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys.contains(keyCode)
    }

    /// The combination as macOS menus write it: ⌃⌥⇧⌘, then the key. All four read "Hyper".
    public var displayName: String {
        if modifiers == .hyper { return "Hyper " + keyName }
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }

    /// The key alone: its symbol or name for keys that type nothing, else what it typed.
    public var keyName: String {
        if let name = Self.specialKeyNames[keyCode] { return name }
        if let character, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return character.uppercased()
        }
        if let name = Self.usLetters[keyCode] { return name }
        return "Key \(keyCode)"
    }

    /// Keys that type nothing visible, by key code (the US-layout hardware codes macOS uses on every layout).
    public static let specialKeyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// What the letter and digit keys type on a US layout, for combinations saved without a character.
    static let usLetters: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
    ]

    public static let functionKeys = Set(specialKeyNames.filter { $0.value.hasPrefix("F") }.keys)

    /// Key codes used by name elsewhere.
    public enum Code {
        public static let p: UInt16 = 35
        public static let space: UInt16 = 49
        public static let tab: UInt16 = 48
        public static let escape: UInt16 = 53
        public static let f18: UInt16 = 79
        public static let capsLock: UInt16 = 57
        public static let leftCommand: UInt16 = 55
        public static let rightCommand: UInt16 = 54
        public static let leftControl: UInt16 = 59
        public static let rightControl: UInt16 = 62
    }
}
