import Foundation

/// What a trigger does when its keys are pressed.
public enum TriggerAction: Hashable, Sendable {
    /// Press other keys instead (a remap): ⌘← for Home, say, only in one app.
    case sendKeys(KeyCombo)
    case openApp(AppRef)
    /// Run one of Apple's Shortcuts, by its name in the Shortcuts app.
    case runShortcut(String)
    /// Send the keys themselves straight to the app in front, ahead of macOS and other apps'
    /// global shortcuts: one shortcut for a remote session without a whole passthrough entry.
    case passThrough
    /// A web link, or a file or folder path ("~/…" works).
    case open(String)

    public var kind: Kind {
        switch self {
        case .sendKeys: .sendKeys
        case .openApp: .openApp
        case .runShortcut: .runShortcut
        case .passThrough: .passThrough
        case .open: .open
        }
    }

    /// The action's kind alone, as the editor's tiles and the config file name it.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case sendKeys, openApp, runShortcut, passThrough, open
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .sendKeys: "Send other keys"
            case .openApp: "Open an app"
            case .runShortcut: "Run a Shortcut"
            case .passThrough: "Pass keys to the app"
            case .open: "Open a link or file"
            }
        }

        /// How the "New trigger…" menu says it, after "A trigger that…".
        public var menuTitle: String {
            switch self {
            case .sendKeys: "Sends other keys"
            case .openApp: "Opens an app"
            case .runShortcut: "Runs a Shortcut"
            case .passThrough: "Passes keys to the app"
            case .open: "Opens a link or file"
            }
        }

        public var symbol: String {
            switch self {
            case .sendKeys: "arrow.left.arrow.right"
            case .openApp: "square.grid.2x2"
            case .runShortcut: "square.stack.3d.up"
            case .passThrough: "arrow.right.to.line"
            case .open: "link"
            }
        }

        /// The action this kind starts as, when picked in the editor.
        public var blank: TriggerAction {
            switch self {
            case .sendKeys: .sendKeys(KeyCombo(keyCode: 123, modifiers: .command))
            case .openApp: .openApp(AppRef(bundleID: "", name: ""))
            case .runShortcut: .runShortcut("")
            case .passThrough: .passThrough
            case .open: .open("")
            }
        }
    }

    /// One line for the menu: what happens.
    public var summary: String {
        switch self {
        case let .sendKeys(keys): "Sends \(keys.displayName)"
        case let .openApp(app): app.name.isEmpty ? "Opens an app" : "Opens \(app.name)"
        case let .runShortcut(name): name.isEmpty ? "Runs a Shortcut" : "Runs “\(name)”"
        case .passThrough: "Passes the keys to the app"
        case let .open(target): target.isEmpty ? "Opens a link" : "Opens \(target)"
        }
    }
}

/// A shortcut of your own: its keys (one or several), what they do, and where. With no apps it works everywhere except
/// inside a passthrough app (whose keys belong to the session); name a passthrough app to have it
/// work there too.
public struct Trigger: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Any of these keys sets it off; none leaves it waiting for keys.
    public var keys: [KeyCombo]
    public var action: TriggerAction
    /// Only in these apps; empty for everywhere.
    public var apps: [AppRef]
    public var conditions: ConditionSet
    /// Fields in the config file MacsBored doesn't know, written back as they were.
    public var extra: JSONFields

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, keys: [KeyCombo],
                action: TriggerAction, apps: [AppRef] = [], conditions: ConditionSet = ConditionSet(),
                extra: JSONFields = JSONFields()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.keys = keys
        self.action = action
        self.apps = apps
        self.conditions = conditions
        self.extra = extra
    }

    /// Whether pressing `keys` runs this trigger now.
    public func fires(on pressed: KeyCombo, context: AppContext, passthroughActive: Bool) -> Bool {
        guard isEnabled, keys.contains(pressed) else { return false }
        if apps.isEmpty {
            if passthroughActive { return false }
        } else if !apps.contains(where: { $0.bundleID == context.bundleID }) {
            return false
        }
        return conditions.isSatisfied(by: context)
    }
}
