#if canImport(AppKit)
import AppKit
import ServiceManagement

/// The Hyper key: Caps Lock is remapped (with `hidutil`, for this login session) to F18, which the
/// keyboard tap turns into ⌃⌥⇧⌘ held together. Switching it off, or quitting, puts Caps Lock back.
/// A key mapping something else set (Karabiner, another tool) is left alone and Hyper stays off.
enum HyperKeyMapping {
    private static let capsLock: UInt64 = 0x7_0000_0039
    private static let f18: UInt64 = 0x7_0000_006D

    enum Outcome { case on, off, blockedByOtherMapping }

    @discardableResult
    static func set(_ on: Bool) -> Outcome {
        let current = hidutil(["property", "--get", "UserKeyMapping"]) ?? ""
        let ours = current.contains("30064771129") && current.contains("30064771181")   // the two in decimal
        let compact = current.filter { !$0.isWhitespace }
        let empty = compact.isEmpty || compact == "(null)" || compact == "()"
        if on {
            guard empty || ours else { return .blockedByOtherMapping }
            let mapping = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\#(capsLock),"HIDKeyboardModifierMappingDst":\#(f18)}]}"#
            _ = hidutil(["property", "--set", mapping])
            return .on
        }
        if ours { _ = hidutil(["property", "--set", #"{"UserKeyMapping":[]}"#]) }
        return .off
    }

    private static func hidutil(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its prompt, and opens the Accessibility list for the switch.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
