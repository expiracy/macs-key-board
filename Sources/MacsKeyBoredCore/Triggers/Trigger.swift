import Foundation

/// What a trigger does when its keys are pressed.
public enum TriggerAction: Codable, Hashable, Sendable {
    /// Press other keys instead (a remap): ⌘← for Home, say, only in one app.
    case sendShortcut(KeyCombo)
    case openApp(AppRef)
    case openURL(String)
    /// A line for `/bin/zsh -lc`, run in the background.
    case runShell(String)
    /// Text typed as if from the keyboard: a snippet.
    case typeText(String)
    /// Passthrough's pause, as the pause shortcut does.
    case togglePause
    case toggleKeepAwake

    public var kind: Kind {
        switch self {
        case .sendShortcut: .sendShortcut
        case .openApp: .openApp
        case .openURL: .openURL
        case .runShell: .runShell
        case .typeText: .typeText
        case .togglePause: .togglePause
        case .toggleKeepAwake: .toggleKeepAwake
        }
    }

    /// The action's kind alone, for the editor's picker.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case sendShortcut, openApp, openURL, runShell, typeText, togglePause, toggleKeepAwake
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .sendShortcut: "Send other keys"
            case .openApp: "Open an app"
            case .openURL: "Open a link or file"
            case .runShell: "Run a shell command"
            case .typeText: "Type text"
            case .togglePause: "Pause or resume passthrough"
            case .toggleKeepAwake: "Keep awake on or off"
            }
        }

        public var symbol: String {
            switch self {
            case .sendShortcut: "arrow.triangle.swap"
            case .openApp: "app.badge"
            case .openURL: "link"
            case .runShell: "terminal"
            case .typeText: "text.cursor"
            case .togglePause: "pause.circle"
            case .toggleKeepAwake: "cup.and.saucer"
            }
        }

        /// The action this kind starts as, when picked in the editor.
        public var blank: TriggerAction {
            switch self {
            case .sendShortcut: .sendShortcut(KeyCombo(keyCode: 123, modifiers: .command))
            case .openApp: .openApp(AppRef(bundleID: "com.apple.Terminal", name: "Terminal"))
            case .openURL: .openURL("https://")
            case .runShell: .runShell("")
            case .typeText: .typeText("")
            case .togglePause: .togglePause
            case .toggleKeepAwake: .toggleKeepAwake
            }
        }
    }

    /// One line for the menu: what happens.
    public var summary: String {
        switch self {
        case let .sendShortcut(keys): "Sends \(keys.displayName)"
        case let .openApp(app): "Opens \(app.name)"
        case let .openURL(url): "Opens \(url)"
        case let .runShell(command): command.isEmpty ? "Runs a command" : "Runs \(command)"
        case let .typeText(text): "Types “\(text.prefix(24))”"
        case .togglePause: "Pauses passthrough"
        case .toggleKeepAwake: "Keeps the Mac awake"
        }
    }
}

/// A shortcut of your own, BetterTouchTool style: keys, what they do, and where. With no apps it
/// works everywhere except inside a passthrough app (whose keys belong to the session); name a
/// passthrough app to have it work there too.
public struct Trigger: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var shortcut: KeyCombo?
    public var action: TriggerAction
    /// Only in these apps; empty for everywhere.
    public var apps: [AppRef]
    public var conditions: ConditionSet

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, shortcut: KeyCombo?,
                action: TriggerAction, apps: [AppRef] = [], conditions: ConditionSet = ConditionSet()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.shortcut = shortcut
        self.action = action
        self.apps = apps
        self.conditions = conditions
    }

    /// Whether pressing `keys` runs this trigger now.
    public func fires(on keys: KeyCombo, context: AppContext, passthroughActive: Bool) -> Bool {
        guard isEnabled, shortcut == keys else { return false }
        if apps.isEmpty {
            if passthroughActive { return false }
        } else if !apps.contains(where: { $0.bundleID == context.bundleID }) {
            return false
        }
        return conditions.isSatisfied(by: context)
    }

    private enum CodingKeys: String, CodingKey { case id, name, isEnabled, shortcut, action, apps, conditions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        action = try c.decode(TriggerAction.self, forKey: .action)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Trigger"
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        shortcut = try? c.decodeIfPresent(KeyCombo.self, forKey: .shortcut)
        apps = (try? c.decode(LossyArray<AppRef>.self, forKey: .apps))?.elements ?? []
        conditions = (try? c.decode(ConditionSet.self, forKey: .conditions)) ?? ConditionSet()
    }
}
