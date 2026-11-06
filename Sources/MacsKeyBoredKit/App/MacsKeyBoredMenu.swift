#if canImport(AppKit)
import AppKit
import MacsKeyBoredCore

/// The MacsKeyBored dropdown, built like MacsPane's: the main switch beside the name; a "Now" card
/// saying what the app in front gets and the one thing to do about it; any warning with its fix; the
/// general switches; then the passthrough apps and your triggers, each with a pencil, a bin and its switch.
@MainActor
enum MacsKeyBoredMenu {
    static let name = "MacsKeyBored"

    static func content(_ model: MacsKeyBoredModel) -> StatusMenuContent {
        var content = StatusMenuContent()
        let config = model.config
        content.primary = .toggle("Pass shortcuts to remote apps", symbol: "command", isOn: config.passthroughEnabled,
                                  primary: true) { [weak model] in
            guard let model else { return }
            model.setPassthroughEnabled(!model.config.passthroughEnabled)
        }
        content.live = [now(model)]
        if !model.isAuthorized {
            content.warnings.append(.warning("Passthrough and triggers need Accessibility", actionTitle: "Grant") {
                [weak model] in model?.requestAccess()
            })
        } else if !model.tapRunning {
            content.warnings.append(.warning("macOS hasn't let the keyboard tap start yet. Quit and reopen MacsKeyBored."))
        }
        if !model.hotKeySwitchAvailable {
            content.warnings.append(.warning("This macOS doesn't offer the switch for its own shortcuts: only keys other apps would take are passed through."))
        }
        if config.hyperKeyEnabled && model.hyperBlocked {
            content.warnings.append(.warning("Hyper key is off: another tool already remaps keys (Karabiner?)."))
        }
        content.toggles = toggles(model)
        content.groups = [profileGroup(model), triggerGroup(model)]
        return content
    }

    // MARK: - Now

    private static func now(_ model: MacsKeyBoredModel) -> StatusMenuEntry {
        let context = model.context
        let appName = context.appName ?? "This app"
        let pause = model.config.pauseKeys.map { " \($0.displayName) pauses." } ?? ""
        var entry: StatusMenuEntry
        if model.plan.isActive {
            let count = model.systemShortcutsOff
            let capture = model.plan.captureAllKeys && model.tapRunning ? ", and every key" : ""
            entry = .live("Passing keys to \(appName)", symbol: "command",
                          fact: "\(count) macOS shortcuts go to it\(capture).\(pause)",
                          actionTitle: "Pause", accent: true, key: "now") { [weak model] in model?.togglePause() }
        } else if model.isPaused {
            entry = .live("Paused in \(appName)", symbol: "pause.circle",
                          fact: "macOS has its shortcuts back until you switch apps.",
                          actionTitle: "Resume", key: "now") { [weak model] in model?.togglePause() }
        } else if let profile = model.config.profiles.first(where: { $0.isEnabled && $0.covers(bundleID: context.bundleID) }) {
            let failing = profile.conditions.conditions.filter { !$0.isSatisfied(by: context) }
                .map { ($0.negated ? "not: " : "") + $0.kind.title.lowercased() }
            let why = model.config.passthroughEnabled
                ? "Waiting for \(profile.conditions.match == .all ? "" : "any of: ")\(failing.joined(separator: ", "))."
                : "Passthrough is switched off."
            entry = .live("\(appName) is waiting", symbol: "hourglass", fact: why,
                          actionTitle: "Edit", key: "now") { [weak model] in model?.editProfile(profile.id) }
        } else if let bundleID = context.bundleID, bundleID != Bundle.main.bundleIdentifier, let name = context.appName {
            entry = .live(name, symbol: "macwindow", fact: "macOS keeps its shortcuts here.",
                          actionTitle: "Pass through…", key: "now") { [weak model] in
                model?.newProfile(for: AppRef(bundleID: bundleID, name: name))
            }
        } else {
            entry = .live("Nothing to pass through", symbol: "command", fact: "Bring an app to the front.", key: "now")
        }
        if let bundleID = context.bundleID { entry.appIcon = AppIcons.icon(bundleID: bundleID) }
        return entry
    }

    // MARK: - General

    private static func toggles(_ model: MacsKeyBoredModel) -> [StatusMenuEntry] {
        let config = model.config
        var pause = StatusMenuEntry.toggle("Pause shortcut", symbol: "pause.circle", isOn: config.pauseKeys != nil) {
            [weak model] in
            guard let model else { return }
            model.setPauseKeys(model.config.pauseKeys == nil ? MacsKeyBoredConfig.defaultPauseKeys : nil)
        }
        pause.trailing = (config.pauseKeys ?? MacsKeyBoredConfig.defaultPauseKeys).displayName
        var hyper = StatusMenuEntry.toggle("Caps Lock is Hyper", symbol: "capslock", isOn: config.hyperKeyEnabled) {
            [weak model] in
            guard let model else { return }
            model.setHyperKey(!model.config.hyperKeyEnabled)
        }
        hyper.trailing = "⌃⌥⇧⌘"
        return [
            .toggle("Open at login", symbol: "power", isOn: LoginItem.isEnabled) {
                LoginItem.setEnabled(!LoginItem.isEnabled)
            },
            pause,
            hyper,
            .toggle("Keep awake", symbol: "cup.and.saucer", isOn: model.keepAwakeOn) { [weak model] in
                guard let model else { return }
                model.setKeepAwake(!model.keepAwakeOn)
            },
        ]
    }

    // MARK: - Lists

    private static func profileGroup(_ model: MacsKeyBoredModel) -> StatusMenuGroup {
        let rows = model.config.profiles.map { profile in
            var row = StatusMenuEntry.toggle(profile.name, symbol: "macwindow", isOn: profile.isEnabled,
                                             key: "profile-\(profile.id)",
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editProfile(profile.id) }),
                                             trash: ("Delete \(profile.name)", { [weak model] in model?.deleteProfile(profile.id) })) {
                [weak model] in model?.toggleProfile(profile.id)
            }
            row.appIcon = profile.apps.first.flatMap { AppIcons.icon(bundleID: $0.bundleID) }
            let conditions = profile.conditions.conditions.count
            row.trailing = conditions == 0 ? nil : conditions == 1
                ? profile.conditions.conditions[0].kind.title.replacingOccurrences(of: "Window is ", with: "")
                : "\(conditions) conditions"
            return row
        }
        let add = StatusMenuEntry.submenu("Add an app", symbol: "plus", key: "profile-new",
                                          items: addAppItems(model))
        return StatusMenuGroup(title: "Passthrough apps", rows: rows, actions: [add],
                               empty: "None yet. Add Windows App, Citrix Viewer or a virtual machine and macOS's shortcuts reach it instead.")
    }

    /// The front app, the remote-desktop apps installed that have no profile yet, then any app.
    private static func addAppItems(_ model: MacsKeyBoredModel) -> [StatusMenuEntry] {
        let covered = Set(model.config.profiles.flatMap(\.apps).map(\.bundleID))
        var apps: [AppRef] = KnownPassthroughApps.all.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
        if let front = model.context.bundleID, let name = model.context.appName, front != Bundle.main.bundleIdentifier,
           !apps.contains(where: { $0.bundleID == front }) {
            apps.insert(AppRef(bundleID: front, name: name), at: 0)
        }
        var items = apps.filter { !covered.contains($0.bundleID) }.map { app in
            var item = StatusMenuEntry.command(app.name, symbol: "macwindow", key: "add-\(app.bundleID)") {
                [weak model] in model?.newProfile(for: app)
            }
            item.appIcon = AppIcons.icon(bundleID: app.bundleID)
            return item
        }
        items.append(.command("Choose an app…", symbol: "folder", key: "add-choose") { [weak model] in
            AppChooser.choose { app in model?.newProfile(for: app) }
        })
        return items
    }

    private static func triggerGroup(_ model: MacsKeyBoredModel) -> StatusMenuGroup {
        let rows = model.config.triggers.map { trigger in
            var row = StatusMenuEntry.toggle(trigger.name, symbol: trigger.action.kind.symbol, isOn: trigger.isEnabled,
                                             key: "trigger-\(trigger.id)",
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editTrigger(trigger.id) }),
                                             trash: ("Delete \(trigger.name)", { [weak model] in model?.deleteTrigger(trigger.id) })) {
                [weak model] in model?.toggleTrigger(trigger.id)
            }
            row.trailing = trigger.shortcut?.displayName ?? "No keys"
            return row
        }
        let new = StatusMenuEntry.submenu("New trigger", symbol: "plus", key: "trigger-new",
                                          items: TriggerAction.Kind.allCases.map { kind in
            .command(kind.title, symbol: kind.symbol, key: "new-\(kind.rawValue)") { [weak model] in model?.newTrigger(kind) }
        })
        return StatusMenuGroup(title: "Triggers", rows: rows, actions: [new],
                               empty: "None yet. A trigger runs something from any app: keys, an app, a link, a command or text.")
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
