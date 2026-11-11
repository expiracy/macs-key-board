#if canImport(AppKit)
import AppKit
import MacsBoredCore

/// Does what a trigger says: presses other keys, opens an app, a link or a file, or runs one of
/// Apple's Shortcuts. Passing keys through is the keyboard tap's job, so it never reaches here.
enum ActionRunner {
    static func run(_ action: TriggerAction) {
        switch action {
        case let .sendKeys(keys):
            press(keys)
        case let .openApp(app):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
                NSSound.beep(); return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case let .open(text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let url = trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
                ? URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                : URL(string: trimmed)
            guard let url else { NSSound.beep(); return }
            NSWorkspace.shared.open(url)
        case let .runShortcut(name):
            runShortcut(name)
        case .passThrough:
            break
        }
    }

    /// The Shortcuts app's own command line, in the background.
    static func runShortcut(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            if finished.terminationStatus != 0 { DispatchQueue.main.async { NSSound.beep() } }
        }
        do { try process.run() } catch { NSSound.beep() }
    }

    /// The names of your Shortcuts, as the Shortcuts app lists them.
    static func shortcutNames() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
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
}
#endif
