import Foundation

/// An app picked by its bundle identifier, with the name it had when picked (for when it is gone).
public struct AppRef: Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// How the Mac's modifier keys reach a passthrough app.
public enum ModifierLayout: String, CaseIterable, Sendable {
    /// As the app maps them: in Windows App and Citrix ⌘ is usually the Windows key, ⌥ is Alt.
    case asIs
    /// ⌘ and ⌃ swap places, so ⌘C is Ctrl+C in the session and ⌃ becomes the Windows key.
    case swapCommandControl

    public var title: String {
        switch self {
        case .asIs: "As the app maps them"
        case .swapCommandControl: "⌘ is Ctrl, ⌃ is Windows"
        }
    }
}

/// One rule for keeping macOS's shortcuts out of some apps: while one of `apps` is in front and the
/// conditions hold, the chosen system shortcuts are switched off so their keys reach the app, and
/// (`captureAllKeys`) every key goes straight to the app ahead of other apps' global shortcuts.
public struct PassthroughProfile: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var apps: [AppRef]
    public var conditions: ConditionSet
    public var systemShortcuts: Set<SystemShortcutGroup>
    public var captureAllKeys: Bool
    public var modifierLayout: ModifierLayout
    /// Fields in the config file MacsBored doesn't know, written back as they were.
    public var extra: JSONFields

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, apps: [AppRef],
                conditions: ConditionSet = ConditionSet(),
                systemShortcuts: Set<SystemShortcutGroup> = SystemShortcutGroup.defaultSet,
                captureAllKeys: Bool = false, modifierLayout: ModifierLayout = .asIs, extra: JSONFields = JSONFields()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.apps = apps
        self.conditions = conditions
        self.systemShortcuts = systemShortcuts
        self.captureAllKeys = captureAllKeys
        self.modifierLayout = modifierLayout
        self.extra = extra
    }

    public func covers(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return apps.contains { $0.bundleID == bundleID }
    }
}

/// What passthrough does right now: nothing, or which profile is acting for which app.
public struct PassthroughPlan: Equatable, Sendable {
    public var profileID: UUID?
    public var profileName: String?
    /// The app taking the keys.
    public var processID: Int32?
    /// The symbolic hot keys to have switched off.
    public var disabledHotKeys: Set<Int>
    public var captureAllKeys: Bool
    public var modifierLayout: ModifierLayout

    public static let inactive = PassthroughPlan(profileID: nil, profileName: nil, processID: nil,
                                                 disabledHotKeys: [], captureAllKeys: false, modifierLayout: .asIs)

    public var isActive: Bool { profileID != nil }

    public init(profileID: UUID?, profileName: String?, processID: Int32?, disabledHotKeys: Set<Int>,
                captureAllKeys: Bool, modifierLayout: ModifierLayout) {
        self.profileID = profileID
        self.profileName = profileName
        self.processID = processID
        self.disabledHotKeys = disabledHotKeys
        self.captureAllKeys = captureAllKeys
        self.modifierLayout = modifierLayout
    }
}
