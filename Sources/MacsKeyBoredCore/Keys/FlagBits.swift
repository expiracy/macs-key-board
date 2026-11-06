import Foundation

/// A keyboard event's raw flag bits (`CGEventFlags.rawValue`), read and rewritten as `KeyCombo.Modifiers`.
/// Besides each modifier's own bit, an event carries which side's key is down (the IOKit
/// `NX_DEVICE…KEYMASK` bits); remote-desktop clients read those to send left or right Ctrl, so a
/// rewrite keeps them consistent with the modifiers it sets.
public enum FlagBits {
    private struct Bits {
        let modifier: KeyCombo.Modifiers
        let main: UInt64
        let left: UInt64
        let right: UInt64
        var sides: UInt64 { left | right }
    }

    private static let all: [Bits] = [
        Bits(modifier: .control, main: 0x40000, left: 0x1, right: 0x2000),
        Bits(modifier: .shift, main: 0x20000, left: 0x2, right: 0x4),
        Bits(modifier: .command, main: 0x100000, left: 0x8, right: 0x10),
        Bits(modifier: .option, main: 0x80000, left: 0x20, right: 0x40),
    ]

    private static func bits(_ modifier: KeyCombo.Modifiers) -> Bits {
        all.first { $0.modifier == modifier }!
    }

    public static func modifiers(_ raw: UInt64) -> KeyCombo.Modifiers {
        all.reduce(into: []) { result, bits in
            if raw & bits.main != 0 { result.insert(bits.modifier) }
        }
    }

    /// `raw` with exactly `modifiers` held: when ⌘ and ⌃ were swapped, each one's side bits move to the
    /// other; a modifier added (by Hyper) reads as its left key; one removed loses both sides. Every
    /// other bit (Caps Lock, keypad, fn) is left as it was.
    public static func rewrite(_ raw: UInt64, to modifiers: KeyCombo.Modifiers, swappedCommandControl: Bool) -> UInt64 {
        var raw = raw
        if swappedCommandControl {
            let control = bits(.control), command = bits(.command)
            let controlPart = raw & (control.main | control.sides)
            let commandPart = raw & (command.main | command.sides)
            raw &= ~(controlPart | commandPart)
            if controlPart & control.main != 0 { raw |= command.main }
            if controlPart & control.left != 0 { raw |= command.left }
            if controlPart & control.right != 0 { raw |= command.right }
            if commandPart & command.main != 0 { raw |= control.main }
            if commandPart & command.left != 0 { raw |= control.left }
            if commandPart & command.right != 0 { raw |= control.right }
        }
        for bits in all {
            let held = raw & bits.main != 0
            if modifiers.contains(bits.modifier), !held {
                raw |= bits.main | bits.left
            } else if !modifiers.contains(bits.modifier), held || raw & bits.sides != 0 {
                raw &= ~(bits.main | bits.sides)
            }
        }
        return raw
    }
}
