#if canImport(AppKit)
import AppKit
import MacsKeyBoredCore

/// Does what a trigger says: presses other keys, opens an app or a link, runs a command or types text.
/// The two toggles (pause, keep awake) belong to the model, which handles them itself.
enum ActionRunner {
    static func run(_ action: TriggerAction) {
        switch action {
        case let .sendShortcut(keys):
            press(keys)
        case let .openApp(app):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
                NSSound.beep(); return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case let .openURL(text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let url = trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
                ? URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                : URL(string: trimmed)
            guard let url else { NSSound.beep(); return }
            NSWorkspace.shared.open(url)
        case let .runShell(command):
            guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        case let .typeText(text):
            type(text)
        case .togglePause, .toggleKeepAwake:
            break
        }
    }

    /// The keys pressed and let go, with exactly their modifiers, whatever is physically held.
    static func press(_ keys: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keys.keyCode, keyDown: down) else { continue }
            event.flags = CGEventFlags(rawValue: FlagBits.rewrite(0, to: keys.modifiers, swappedCommandControl: false))
            event.setIntegerValueField(.eventSourceUserData, value: KeyboardTap.ownEventTag)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Text typed into the front app, a few characters per event as the system allows.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 20, units.count)])
            index += chunk.count
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: KeyboardTap.ownEventTag)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
}
#endif
