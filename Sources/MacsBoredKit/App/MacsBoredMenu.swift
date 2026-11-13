#if canImport(AppKit)
import AppKit
import MacsBoredCore

/// The MacsBored dropdown, built like MacsPane's: the main switch beside the name; a "Now" box
/// saying what the app in front gets and the one thing to do about it; any warning with its fix; the
/// general switches; then the passthrough apps and your triggers, each with a pencil, a bin and its switch.
@MainActor
enum MacsBoredMenu {
    static let name = "MacsBored"

    static func content(_ model: MacsBoredModel) -> StatusMenuContent {
        var content = StatusMenuContent()
        let config = model.config
        content.primary = .toggle("Pass shortcuts to remote apps", symbol: "command", isOn: config.passthroughEnabled,
                                  primary: true) { [weak model] in
            guard let model else { return }
            model.setPassthroughEnabled(!model.config.passthroughEnabled)
        }
        content.liveFact = statusLine(model)
        content.live = [now(model)]
        content.warnings = warnings(model)
        content.toggles = toggles(model)
        content.groups = [profileGroup(model), triggerGroup(model)]
        return content
    }

    private static func statusLine(_ model: MacsBoredModel) -> String {
        let app = model.context.appName ?? "the app"
        if !model.config.passthroughEnabled { return "Off · macOS keeps all its shortcuts" }
        if model.plan.isActive { return "Passing \(model.systemShortcutsOff) shortcuts to \(app)" }
        if model.isPaused { return "Paused in \(app)" }
        return "On · waiting for a passthrough app"
    }

    // MARK: - Now

    private static func now(_ model: MacsBoredModel) -> StatusMenuEntry {
        let context = model.context
        let appName = context.appName ?? "This app"
        var entry: StatusMenuEntry
        if model.plan.isActive {
            let count = model.systemShortcutsOff
            entry = .live(appName, symbol: "command", fact: count == 1 ? "1 macOS shortcut goes to it" : "\(count) macOS shortcuts go to it",
                          actionTitle: "Pause", accent: true, key: "now") { [weak model] in model?.togglePause() }
        } else if model.isPaused {
            entry = .live(appName, symbol: "pause.circle", fact: "Paused: macOS has its shortcuts back",
                          actionTitle: "Resume", key: "now") { [weak model] in model?.togglePause() }
        } else if let profile = model.config.profiles.first(where: { $0.isEnabled && $0.covers(bundleID: context.bundleID) }) {
            entry = .live(appName, symbol: "hourglass", fact: model.config.passthroughEnabled ? "Waiting for its conditions" : "Passthrough is switched off",
                          actionTitle: "Edit", key: "now") { [weak model] in model?.editProfile(profile.id) }
        } else if let bundleID = context.bundleID, bundleID != Bundle.main.bundleIdentifier, let name = context.appName {
            entry = .live(name, symbol: "macwindow", fact: "macOS keeps its shortcuts here",
                          actionTitle: "Add", key: "now") { [weak model] in
                model?.newProfile(for: AppRef(bundleID: bundleID, name: name))
            }
        } else {
            entry = .live("Nothing to pass through", symbol: "command", fact: "Bring a remote desktop to the front", key: "now")
        }
        if let bundleID = context.bundleID { entry.appIcon = AppIcons.icon(bundleID: bundleID) }
        return entry
    }

    // MARK: - Warnings

    private static func warnings(_ model: MacsBoredModel) -> [StatusMenuEntry] {
        var warnings: [StatusMenuEntry] = []
        if let issue = model.fileErrors.first {
            let line = issue.line.map { "config.json line \($0) isn't valid" } ?? "config.json isn't valid"
            var row = StatusMenuEntry.warning(line, actionTitle: "Show") { [weak model] in model?.openConfigFile() }
            row.trailing = issue.message
            warnings.append(row)
        }
        if !model.isAuthorized {
            warnings.append(.warning("Needs Accessibility", actionTitle: "Grant") { [weak model] in model?.requestAccess() })
        } else if !model.tapRunning {
            warnings.append(.warning("Keyboard tap isn't running", actionTitle: "Relaunch") { Relaunch.now() })
        }
        if !model.hotKeySwitchAvailable {
            warnings.append(.warning("macOS's own shortcuts can't be switched here"))
        }
        if model.config.hyperKeyEnabled && model.hyperBlocked {
            warnings.append(.warning("Hyper is off: another tool remaps keys"))
        }
        return warnings
    }

    // MARK: - General

    private static func toggles(_ model: MacsBoredModel) -> [StatusMenuEntry] {
        let config = model.config
        var pause = StatusMenuEntry.toggle("Pause shortcut", symbol: "pause.circle", isOn: config.pauseKeys != nil) {
            [weak model] in
            guard let model else { return }
            model.setPauseKeys(model.config.pauseKeys == nil ? MacsBoredConfig.defaultPauseKeys : nil)
        }
        pause.trailing = (config.pauseKeys ?? MacsBoredConfig.defaultPauseKeys).displayName
        var hyper = StatusMenuEntry.toggle("Caps Lock as Hyper", symbol: "capslock", isOn: config.hyperKeyEnabled) {
            [weak model] in
            guard let model else { return }
            model.setHyperKey(!model.config.hyperKeyEnabled)
        }
        hyper.trailing = "⌃⌥⇧⌘"
        var file = StatusMenuEntry.command("Settings file", symbol: "doc.text", key: "settings-file") { [weak model] in
            model?.revealConfigFile()
        }
        file.trailing = "config.json"
        return [
            .toggle("Open at login", symbol: "power", isOn: model.openAtLogin) { [weak model] in
                guard let model else { return }
                model.setOpenAtLogin(!model.openAtLogin)
            },
            pause,
            hyper,
            file,
        ]
    }

    // MARK: - Lists

    private static func profileGroup(_ model: MacsBoredModel) -> StatusMenuGroup {
        let rows = model.config.profiles.map { profile in
            var row = StatusMenuEntry.toggle(profile.name, symbol: "macwindow", isOn: profile.isEnabled,
                                             key: "profile-\(profile.id)",
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editProfile(profile.id) }),
                                             trash: ("Delete \(profile.name)", { [weak model] in model?.deleteProfile(profile.id) })) {
                [weak model] in model?.toggleProfile(profile.id)
            }
            row.appIcon = profile.apps.first.flatMap { AppIcons.icon(bundleID: $0.bundleID) }
            return row
        }
        return StatusMenuGroup(title: "Passthrough apps", rows: rows,
                               empty: "None yet. Click New to give Windows App, Citrix Viewer or a virtual machine macOS's shortcuts.")
    }

    private static func triggerGroup(_ model: MacsBoredModel) -> StatusMenuGroup {
        let rows = model.config.triggers.map { trigger in
            var row = StatusMenuEntry.toggle(trigger.name, symbol: trigger.action.kind.symbol, isOn: trigger.isEnabled,
                                             key: "trigger-\(trigger.id)",
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editTrigger(trigger.id) }),
                                             trash: ("Delete \(trigger.name)", { [weak model] in model?.deleteTrigger(trigger.id) })) {
                [weak model] in model?.toggleTrigger(trigger.id)
            }
            row.trailing = trigger.keys.isEmpty ? "No keys"
                : trigger.keys.count == 1 ? trigger.keys[0].displayName
                : "\(trigger.keys[0].displayName) +\(trigger.keys.count - 1)"
            return row
        }
        return StatusMenuGroup(title: "Triggers", rows: rows,
                               empty: "None yet. Click New to make one: remap keys, open something or run a Shortcut.")
    }
}

/// Starts a fresh copy of the app and quits this one, for when macOS won't start the keyboard tap.
enum Relaunch {
    static func now() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Picks an app from /Applications.
@MainActor
enum AppChooser {
    static func choose(_ picked: @escaping (AppRef) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        picked(AppRef(bundleID: id, name: name))
    }
}
#endif
