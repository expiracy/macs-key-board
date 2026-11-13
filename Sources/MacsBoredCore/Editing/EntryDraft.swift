import Foundation

/// What the editor holds while you set something up. Its four tabs are the four different things
/// MacsBored does: remap keys, open something, run a Shortcut, and pass keys through (a whole app,
/// or only some keys). Every tab shares the name, the keys, the apps and the conditions, so moving
/// between tabs never loses them; `result` is what the current tab makes of it all.
public struct EntryDraft: Equatable, Sendable {
    public enum Tab: String, CaseIterable, Sendable {
        case remap, open, shortcut, passthrough

        public var title: String {
            switch self {
            case .remap: "Remap Keys"
            case .open: "Open"
            case .shortcut: "Run Shortcut"
            case .passthrough: "Passthrough"
            }
        }

        public var symbol: String {
            switch self {
            case .remap: "arrow.left.arrow.right"
            case .open: "arrow.up.forward.square"
            case .shortcut: "square.stack.3d.up"
            case .passthrough: "arrow.right.to.line"
            }
        }
    }

    public enum PassMode: Sendable { case wholeApp, someKeys }
    public enum OpenTarget: Sendable { case app, link, file }

    /// What the draft was opened on, so saving replaces it.
    public enum Origin: Equatable, Sendable {
        case new
        case trigger(UUID)
        case profile(UUID)
    }

    public enum Result: Equatable, Sendable {
        case trigger(Trigger)
        case profile(PassthroughProfile)
    }

    public var origin: Origin = .new
    public var tab: Tab = .remap
    public var passMode: PassMode = .wholeApp
    public var openTarget: OpenTarget = .app
    /// Your own name; empty follows `suggestedName`.
    public var customName = ""
    public var isEnabled = true
    /// The keys that set a trigger off: one, or several (say, each shortcut a session should get).
    public var keys: [KeyCombo] = []
    public var sendKeys: KeyCombo?
    public var app: AppRef?
    public var link = ""
    public var file = ""
    public var shortcutName = ""
    /// A trigger works only in `apps` (a passthrough app always does).
    public var onlyInApps = false
    public var apps: [AppRef] = []
    public var conditions = ConditionSet()
    public var systemShortcuts = SystemShortcutGroup.defaultSet
    public var captureAllKeys = false
    public var modifierLayout = ModifierLayout.asIs
    private var triggerExtra = JSONFields()
    private var profileExtra = JSONFields()
    /// The ID a new entry gets, fixed for the draft so previews and the save agree.
    private var newID = UUID()

    public init() {}

    public init(trigger: Trigger) {
        origin = .trigger(trigger.id)
        isEnabled = trigger.isEnabled
        keys = trigger.keys
        apps = trigger.apps
        onlyInApps = !trigger.apps.isEmpty
        conditions = trigger.conditions
        triggerExtra = trigger.extra
        switch trigger.action {
        case let .sendKeys(send): tab = .remap; sendKeys = send
        case let .openApp(app): tab = .open; openTarget = .app; self.app = app
        case let .open(target):
            tab = .open
            if target.contains("://") { openTarget = .link; link = target } else { openTarget = .file; file = target }
        case let .runShortcut(name): tab = .shortcut; shortcutName = name
        case .passThrough: tab = .passthrough; passMode = .someKeys
        }
        if trigger.name != suggestedName { customName = trigger.name }
    }

    public init(profile: PassthroughProfile) {
        origin = .profile(profile.id)
        tab = .passthrough
        passMode = .wholeApp
        isEnabled = profile.isEnabled
        apps = profile.apps
        onlyInApps = true
        conditions = profile.conditions
        systemShortcuts = profile.systemShortcuts
        captureAllKeys = profile.captureAllKeys
        modifierLayout = profile.modifierLayout
        profileExtra = profile.extra
        if profile.name != suggestedName { customName = profile.name }
    }

    /// A whole app passes through: the draft is a passthrough entry rather than a trigger.
    public var isPassthroughApp: Bool { tab == .passthrough && passMode == .wholeApp }

    public var name: String {
        let own = customName.trimmingCharacters(in: .whitespaces)
        return own.isEmpty ? suggestedName : own
    }

    /// A name that says what it does, used until you give your own.
    public var suggestedName: String {
        switch tab {
        case .remap: return sendKeys.map { "Press \($0.displayName)" } ?? "Remap keys"
        case .shortcut: return shortcutName.isEmpty ? "Run a Shortcut" : shortcutName
        case .passthrough:
            if passMode == .wholeApp { return apps.first?.name ?? "Passthrough app" }
            switch keys.count {
            case 0: return "Pass keys to the app"
            case 1: return "Pass \(keys[0].displayName) to the app"
            case 2: return "Pass \(keys[0].displayName) and \(keys[1].displayName) to the app"
            default: return "Pass \(keys.count) shortcuts to the app"
            }
        case .open:
            switch openTarget {
            case .app: return app.map { "Open \($0.name)" } ?? "Open an app"
            case .link:
                let host = URL(string: link.trimmingCharacters(in: .whitespaces))?.host
                return link.isEmpty ? "Open a link" : "Open \(host ?? link)"
            case .file:
                let last = (file as NSString).lastPathComponent
                return file.isEmpty ? "Open a file" : "Open \(last.isEmpty ? file : last)"
            }
        }
    }

    /// Why it can't be saved yet, as the Save button's neighbour says it; nil when it can.
    public var missing: String? {
        if isPassthroughApp { return apps.isEmpty ? "Add an app to save" : nil }
        guard !keys.isEmpty else { return "Record the keys to save" }
        switch tab {
        case .remap: return sendKeys == nil ? "Choose the keys to press" : nil
        case .shortcut: return shortcutName.trimmingCharacters(in: .whitespaces).isEmpty ? "Choose a Shortcut" : nil
        case .passthrough: return nil
        case .open:
            switch openTarget {
            case .app: return app == nil ? "Choose an app" : nil
            case .link: return link.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a link" : nil
            case .file: return file.trimmingCharacters(in: .whitespaces).isEmpty ? "Choose a file or folder" : nil
            }
        }
    }

    /// The trigger's action, or nil while the tab still needs something.
    private var action: TriggerAction? {
        switch tab {
        case .remap: return sendKeys.map { .sendKeys($0) }
        case .shortcut: return shortcutName.isEmpty ? nil : .runShortcut(shortcutName)
        case .passthrough: return passMode == .someKeys ? .passThrough : nil
        case .open:
            switch openTarget {
            case .app: return app.map { .openApp($0) }
            case .link: return link.isEmpty ? nil : .open(link)
            case .file: return file.isEmpty ? nil : .open(file)
            }
        }
    }

    private var triggerID: UUID {
        if case let .trigger(id) = origin { return id }
        return newID
    }

    private var profileID: UUID {
        if case let .profile(id) = origin { return id }
        return newID
    }


    public var trigger: Trigger? {
        guard !isPassthroughApp, let action else { return nil }
        return Trigger(id: triggerID, name: name, isEnabled: isEnabled, keys: keys, action: action,
                       apps: onlyInApps ? apps : [], conditions: conditions, extra: triggerExtra)
    }

    public var profile: PassthroughProfile? {
        guard isPassthroughApp, !apps.isEmpty else { return nil }
        return PassthroughProfile(id: profileID, name: name, isEnabled: isEnabled, apps: apps, conditions: conditions,
                                  systemShortcuts: systemShortcuts, captureAllKeys: captureAllKeys,
                                  modifierLayout: modifierLayout, extra: profileExtra)
    }

    public var result: Result? {
        guard missing == nil else { return nil }
        if let profile { return .profile(profile) }
        return trigger.map { .trigger($0) }
    }

    /// This entry as `config.json` writes it, with null for whatever it still needs.
    public var preview: String {
        if isPassthroughApp {
            let shown = profile ?? PassthroughProfile(name: name, isEnabled: isEnabled, apps: [], conditions: conditions,
                                                      systemShortcuts: systemShortcuts, captureAllKeys: captureAllKeys,
                                                      modifierLayout: modifierLayout, extra: profileExtra)
            return Writer.profile(shown).written()
        }
        if let trigger { return Writer.trigger(trigger).written() }
        let placeholder = Trigger(name: name, isEnabled: isEnabled, keys: keys, action: .passThrough,
                                  apps: onlyInApps ? apps : [], conditions: conditions, extra: triggerExtra)
        guard case var .object(members) = Writer.trigger(placeholder),
              let index = members.firstIndex(where: { $0.0 == "action" }) else { return "" }
        let kind: TriggerAction.Kind = switch tab {
        case .remap: .sendKeys
        case .shortcut: .runShortcut
        case .passthrough: .passThrough
        case .open: openTarget == .app ? .openApp : .open
        }
        members[index].1 = .object([(kind.rawValue, .null)])
        return JSONValue.object(members).written()
    }
}
