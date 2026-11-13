import Foundation

/// Keys as text, the way the config file holds them: modifiers then the key, joined by "+"
/// ("ctrl+opt+cmd+P", "hyper+N", "cmd+space"). Reading also takes the menu's symbols ("⌃⌥⌘P",
/// "⌘Space") and longer words ("control", "option", "alt", "command"). Keys are named as on a US
/// keyboard, which is how macOS numbers them on every layout.
extension KeyCombo {
    /// The keys `text` names, or nil when it names none (an unknown word, no key, two keys).
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var modifiers: Modifiers = []
        let keyPart: String
        if trimmed.count > 1, trimmed.contains("+") {
            var parts = trimmed.split(separator: "+", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            keyPart = parts.removeLast()
            for word in parts {
                guard let modifier = Self.modifierWords[word.lowercased()] else { return nil }
                modifiers.formUnion(modifier)
            }
        } else {
            var rest = Substring(trimmed)
            if rest.lowercased().hasPrefix("hyper ") {
                modifiers = .hyper
                rest = rest.dropFirst(6)
            }
            while let first = rest.first, let modifier = Self.modifierSymbols[first] {
                modifiers.formUnion(modifier)
                rest = rest.dropFirst()
            }
            keyPart = rest.trimmingCharacters(in: .whitespaces)
        }
        guard let code = Self.keyCode(named: keyPart) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    /// The keys as the config file writes them. A key with no name here is written by its number ("key105").
    public var text: String {
        let key = Self.textNames[keyCode] ?? "key\(keyCode)"
        if modifiers == .hyper { return "hyper+" + key }
        let words: [(Modifiers, String)] = [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
        return (words.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
    }

    private static let modifierWords: [String: Modifiers] = [
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
        "hyper": .hyper,
    ]

    private static let modifierSymbols: [Character: Modifiers] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]

    /// Each named key's one written name: letters and digits as typed, everything else a word.
    static let textNames: [UInt16: String] = {
        var names = usLetters
        let words: [UInt16: String] = [
            36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape", 76: "enter", 117: "forwarddelete",
            123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        ]
        names.merge(words) { $1 }
        for (code, name) in specialKeyNames where name.hasPrefix("F") { names[code] = name }
        return names
    }()

    /// Every name a key goes by, lowercased: its written name, the menu's symbol and a few others.
    private static let namesToCodes: [String: UInt16] = {
        var codes: [String: UInt16] = [:]
        for (code, name) in textNames { codes[name.lowercased()] = code }
        for (code, name) in specialKeyNames { codes[name.lowercased()] = code }
        let aliases: [String: UInt16] = ["esc": 53, "backspace": 51, "ret": 36, "fwddelete": 117, "del": 117]
        codes.merge(aliases) { current, _ in current }
        return codes
    }()

    static func keyCode(named name: String) -> UInt16? {
        guard !name.isEmpty else { return nil }
        let lower = name.lowercased()
        if let code = namesToCodes[lower] { return code }
        if lower.hasPrefix("key"), let code = UInt16(lower.dropFirst(3)), code < 128 { return code }
        return nil
    }
}
