import Foundation

/// An app picked by its bundle identifier, with the name it had when picked (for when it is gone).
public struct AppRef: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// How the Mac's modifier keys reach a passthrough app.
public enum ModifierLayout: String, Codable, CaseIterable, Sendable {
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
public struct PassthroughProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var apps: [AppRef]
    public var conditions: ConditionSet
    public var systemShortcuts: Set<SystemShortcutGroup>
    public var captureAllKeys: Bool
    public var modifierLayout: ModifierLayout

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, apps: [AppRef],
                conditions: ConditionSet = ConditionSet(),
                systemShortcuts: Set<SystemShortcutGroup> = SystemShortcutGroup.defaultSet,
                captureAllKeys: Bool = false, modifierLayout: ModifierLayout = .asIs) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.apps = apps
        self.conditions = conditions
        self.systemShortcuts = systemShortcuts
        self.captureAllKeys = captureAllKeys
        self.modifierLayout = modifierLayout
    }

    public func covers(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return apps.contains { $0.bundleID == bundleID }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, apps, conditions, systemShortcuts, captureAllKeys, modifierLayout
    }

    /// Fields this build doesn't know (a shortcut group from a later version) are skipped, not fatal.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Passthrough"
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        apps = (try? c.decode(LossyArray<AppRef>.self, forKey: .apps))?.elements ?? []
        conditions = (try? c.decode(ConditionSet.self, forKey: .conditions)) ?? ConditionSet()
        let groups = (try? c.decode([String].self, forKey: .systemShortcuts))
        systemShortcuts = groups.map { Set($0.compactMap(SystemShortcutGroup.init(rawValue:))) }
            ?? SystemShortcutGroup.defaultSet
        captureAllKeys = (try? c.decode(Bool.self, forKey: .captureAllKeys)) ?? false
        modifierLayout = (try? c.decode(ModifierLayout.self, forKey: .modifierLayout)) ?? .asIs
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(apps, forKey: .apps)
        try c.encode(conditions, forKey: .conditions)
        try c.encode(systemShortcuts.map(\.rawValue).sorted(), forKey: .systemShortcuts)
        try c.encode(captureAllKeys, forKey: .captureAllKeys)
        try c.encode(modifierLayout, forKey: .modifierLayout)
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
