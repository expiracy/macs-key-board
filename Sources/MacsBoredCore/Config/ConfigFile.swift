import Foundation

/// The settings file, `config.json`: how it reads and how it is written. It is made to be edited by
/// hand, by scripts and by AI agents, so values are words people write (keys as "ctrl+opt+cmd+P",
/// apps as bundle IDs, times as "09:00"), entries need no IDs, every field but an app or an action
/// has a default, and a mistake is reported with its line instead of being dropped quietly. Fields
/// MacsBored doesn't know are kept and written back.
///
///     {
///       "enabled": true,
///       "pauseKeys": "ctrl+opt+cmd+P",
///       "passthrough": [{ "name": "Windows App", "apps": ["com.microsoft.rdc.macos"] }],
///       "triggers": [{ "name": "Notes", "keys": "ctrl+opt+N", "action": { "openApp": "com.apple.Notes" } }]
///     }
public enum ConfigFile {
    public static let schemaName = "config.schema.json"

    /// Something about the file worth saying: an error (the file isn't used until it's fixed) or a
    /// warning (it's used, but something in it is ignored or kept as it was).
    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public var line: Int?
        public var message: String
        public var isWarning: Bool

        public init(line: Int?, message: String, isWarning: Bool = false) {
            self.line = line
            self.message = message
            self.isWarning = isWarning
        }

        public var description: String {
            (line.map { "Line \($0): " } ?? "") + (isWarning ? "warning: " : "") + message
        }
    }

    public struct Reading: Sendable {
        /// The settings, or nil when the file has an error.
        public var config: MacsBoredConfig?
        public var issues: [Issue]

        public var errors: [Issue] { issues.filter { !$0.isWarning } }
    }

    public static func read(_ data: Data) -> Reading {
        let node: JSONNode
        do {
            node = try JSONNode.parse(data)
        } catch let error as JSONParseError {
            return Reading(config: nil, issues: [Issue(line: error.line, message: error.message)])
        } catch {
            return Reading(config: nil, issues: [Issue(line: nil, message: "The file can't be read.")])
        }
        guard node.object != nil else {
            return Reading(config: nil, issues: [Issue(line: node.line, message: "The settings must be one object, starting with {.")])
        }
        var reader = Reader()
        let config = LegacyConfig.isLegacy(node) ? LegacyConfig.convert(node, issues: &reader.issues) : reader.config(node)
        let issues = reader.issues.enumerated()
            .sorted { ($0.element.line ?? 0, $0.offset) < ($1.element.line ?? 0, $1.offset) }.map(\.element)
        return Reading(config: issues.contains { !$0.isWarning } ? nil : config, issues: issues)
    }

    public static func written(_ config: MacsBoredConfig) -> String {
        Writer.value(config).written()
    }

    // MARK: - Names the file uses

    static let actionNames: [TriggerAction.Kind] = TriggerAction.Kind.allCases

    static let conditionNames: [(String, Condition.Kind)] = [
        ("fullScreen", .fullScreen), ("fillsScreen", .fillsScreen), ("windowTitleContains", .windowTitleContains("")),
        ("externalDisplay", .externalDisplay), ("onBattery", .onBattery), ("timeBetween", .timeBetween(start: 0, end: 0)),
        ("capsLock", .capsLock),
    ]

    static func name(of kind: Condition.Kind) -> String {
        switch kind {
        case .fullScreen: "fullScreen"
        case .fillsScreen: "fillsScreen"
        case .windowTitleContains: "windowTitleContains"
        case .externalDisplay: "externalDisplay"
        case .onBattery: "onBattery"
        case .timeBetween: "timeBetween"
        case .capsLock: "capsLock"
        }
    }

    static func listed(_ words: [String], last: String = "or") -> String {
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " \(last) " + words.last!
    }

    /// "09:00" for 540 minutes.
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func minutes(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}

// MARK: - Reading

private struct Reader {
    var issues: [ConfigFile.Issue] = []

    mutating func error(_ node: JSONNode, _ message: String) {
        issues.append(.init(line: node.line, message: message))
    }

    mutating func warn(_ node: JSONNode, _ message: String) {
        issues.append(.init(line: node.line, message: message, isWarning: true))
    }

    /// The members not in `known`, kept, each with a warning.
    mutating func extras(_ node: JSONNode, known: Set<String>, what: String) -> JSONFields {
        var kept: [(String, JSONValue)] = []
        for member in node.object ?? [] where !known.contains(member.key) {
            warn(member.node, "“\(member.key)” isn't \(what); it's kept as it is.")
            kept.append((member.key, member.node.value))
        }
        return JSONFields(kept)
    }

    mutating func bool(_ node: JSONNode, _ key: String, default value: Bool) -> Bool {
        guard let field = node[key] else { return value }
        guard let bool = field.bool else { error(field, "“\(key)” should be true or false."); return value }
        return bool
    }

    mutating func string(_ node: JSONNode, _ key: String) -> String? {
        guard let field = node[key], !field.isNull else { return nil }
        guard let text = field.string else { error(field, "“\(key)” should be text in quotes."); return nil }
        return text
    }

    mutating func list(_ node: JSONNode, _ key: String) -> [JSONNode]? {
        guard let field = node[key], !field.isNull else { return nil }
        guard let items = field.array else { error(field, "“\(key)” should be a list in [brackets]."); return nil }
        return items
    }

    mutating func keys(_ node: JSONNode, forTrigger: Bool) -> KeyCombo? {
        guard let text = node.string else {
            error(node, "Keys should be text in quotes, like \"ctrl+opt+cmd+P\".")
            return nil
        }
        guard let keys = KeyCombo(text: text) else {
            error(node, "“\(text)” isn't keys MacsBored knows. Write them like ctrl+opt+cmd+P or hyper+N.")
            return nil
        }
        if forTrigger, !keys.isUsableAsTrigger {
            error(node, "“\(text)” needs ⌘, ⌃ or ⌥ (or an F-key), or it would take over typing.")
            return nil
        }
        return keys
    }

    mutating func app(_ node: JSONNode) -> AppRef? {
        if let id = node.string?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
            return AppRef(bundleID: id, name: KnownPassthroughApps.name(for: id) ?? id)
        }
        if let id = node["bundleID"]?.string, !id.isEmpty {
            return AppRef(bundleID: id, name: node["name"]?.string ?? KnownPassthroughApps.name(for: id) ?? id)
        }
        error(node, "An app is its bundle ID in quotes, like \"com.microsoft.rdc.macos\".")
        return nil
    }

    mutating func apps(_ node: JSONNode) -> [AppRef] {
        (list(node, "apps") ?? []).compactMap { app($0) }
    }

    mutating func config(_ node: JSONNode) -> MacsBoredConfig {
        var config = MacsBoredConfig()
        config.passthroughEnabled = bool(node, "enabled", default: true)
        if let field = node["openAtLogin"], !field.isNull {
            if let on = field.bool { config.openAtLogin = on } else { error(field, "“openAtLogin” should be true or false.") }
        }
        if let field = node["pauseKeys"] {
            config.pauseKeys = field.isNull ? nil : keys(field, forTrigger: true)
        }
        config.hyperKeyEnabled = bool(node, "capsLockAsHyper", default: false)
        config.setupCompleted = bool(node, "setupCompleted", default: false)
        for item in list(node, "passthrough") ?? [] {
            if let profile = profile(item) { config.profiles.append(profile) }
        }
        for item in list(node, "triggers") ?? [] {
            if let trigger = trigger(item) { config.triggers.append(trigger) }
        }
        config.extra = extras(node, known: ["$schema", "enabled", "openAtLogin", "pauseKeys", "capsLockAsHyper",
                                            "setupCompleted", "passthrough", "triggers"],
                              what: "a MacsBored setting")
        return config
    }

    mutating func profile(_ node: JSONNode) -> PassthroughProfile? {
        guard node.object != nil else { error(node, "Each passthrough entry should be an object in {braces}."); return nil }
        let apps = apps(node)
        if apps.isEmpty, node["apps"]?.array?.isEmpty ?? true {
            error(node["apps"] ?? node, "A passthrough entry needs at least one app, by bundle ID.")
        }
        var shortcuts = SystemShortcutGroup.defaultSet
        if let field = node["shortcuts"] {
            if field.string == "all" {
                shortcuts = Set(SystemShortcutGroup.allCases)
            } else if let items = field.array {
                shortcuts = []
                for item in items {
                    if let name = item.string, let group = SystemShortcutGroup(rawValue: name) {
                        shortcuts.insert(group)
                    } else {
                        error(item, "“\(item.string ?? "?")” isn't a shortcut group. Use "
                              + SystemShortcutGroup.allCases.map(\.rawValue).joined(separator: ", ") + ".")
                    }
                }
            } else {
                error(field, "“shortcuts” should be a list of shortcut groups, or \"all\".")
            }
        }
        var layout = ModifierLayout.asIs
        if let text = string(node, "modifiers") {
            if let parsed = ModifierLayout(rawValue: text) { layout = parsed } else {
                error(node["modifiers"]!, "“\(text)” isn't a modifier layout. Use asIs or swapCommandControl.")
            }
        }
        return PassthroughProfile(
            name: string(node, "name") ?? apps.first?.name ?? "Passthrough",
            isEnabled: bool(node, "enabled", default: true),
            apps: apps,
            conditions: conditions(node),
            systemShortcuts: shortcuts,
            captureAllKeys: bool(node, "sendEveryKey", default: false),
            modifierLayout: layout,
            extra: extras(node, known: ["name", "enabled", "apps", "shortcuts", "sendEveryKey", "modifiers", "when"],
                          what: "a passthrough field"))
    }

    mutating func trigger(_ node: JSONNode) -> Trigger? {
        guard node.object != nil else { error(node, "Each trigger should be an object in {braces}."); return nil }
        var combos: [KeyCombo] = []
        if let field = node["keys"], !field.isNull {
            if let list = field.array {
                combos = list.compactMap { keys($0, forTrigger: true) }
            } else if let one = keys(field, forTrigger: true) {
                combos = [one]
            }
        }
        guard let action = action(node) else { return nil }
        return Trigger(name: string(node, "name") ?? "Trigger",
                       isEnabled: bool(node, "enabled", default: true),
                       keys: combos,
                       action: action,
                       apps: apps(node),
                       conditions: conditions(node),
                       extra: extras(node, known: ["name", "enabled", "keys", "action", "apps", "when"],
                                     what: "a trigger field"))
    }

    mutating func action(_ trigger: JSONNode) -> TriggerAction? {
        let example = "A trigger needs an action, like { \"openApp\": \"com.apple.Notes\" }."
        guard let node = trigger["action"], let members = node.object, !members.isEmpty else {
            error(trigger["action"] ?? trigger, example)
            return nil
        }
        guard members.count == 1, let member = members.first else {
            error(node, "An action has one kind, but this one has \(members.count): \(members.map(\.key).joined(separator: ", ")).")
            return nil
        }
        guard let kind = TriggerAction.Kind(rawValue: member.key) else {
            error(member.node, "“\(member.key)” isn't an action. Use "
                  + ConfigFile.listed(ConfigFile.actionNames.map(\.rawValue)) + ".")
            return nil
        }
        let value = member.node
        switch kind {
        case .sendKeys:
            return keys(value, forTrigger: false).map { .sendKeys($0) }
        case .openApp:
            return app(value).map { .openApp($0) }
        case .runShortcut:
            guard let name = value.string, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                error(value, "Name the Shortcut as the Shortcuts app does, in quotes.")
                return nil
            }
            return .runShortcut(name)
        case .passThrough:
            guard value.bool == true else { error(value, "Write “passThrough” as { \"passThrough\": true }."); return nil }
            return .passThrough
        case .open:
            guard let target = value.string, !target.trimmingCharacters(in: .whitespaces).isEmpty else {
                error(value, "“open” takes a link or a file path in quotes.")
                return nil
            }
            return .open(target)
        }
    }

    mutating func conditions(_ owner: JSONNode) -> ConditionSet {
        guard let node = owner["when"], !node.isNull else { return ConditionSet() }
        var match = ConditionMatch.all
        let items: [JSONNode]
        if let list = node.array {
            items = list
        } else if let members = node.object, members.count == 1, let first = members.first,
                  let kind = ConditionMatch(rawValue: first.key), let list = first.node.array {
            match = kind
            items = list
        } else {
            error(node, "“when” should be a list of conditions, or { \"any\": [ … ] }.")
            return ConditionSet()
        }
        return ConditionSet(match: match, conditions: items.compactMap { condition($0) })
    }

    mutating func condition(_ node: JSONNode) -> Condition? {
        let negated = node["unless"] != nil
        guard let head = node["if"] ?? node["unless"] else {
            error(node, "A condition starts with \"if\" or \"unless\", like { \"if\": \"fullScreen\" }.")
            return nil
        }
        guard let name = head.string, let template = ConditionFile.kind(named: name) else {
            error(head, "“\(head.string ?? "?")” isn't a condition. Use "
                  + ConfigFile.listed(ConfigFile.conditionNames.map(\.0)) + ".")
            return nil
        }
        let kind: Condition.Kind
        switch template {
        case .windowTitleContains:
            guard let text = string(node, "text") else {
                error(node, "“windowTitleContains” needs the text, like \"text\": \"Prod\".")
                return nil
            }
            kind = .windowTitleContains(text)
        case .timeBetween:
            var bounds: [Int] = []
            for key in ["from", "to"] {
                guard let field = node[key], let text = field.string else {
                    error(node, "“timeBetween” needs \"from\" and \"to\", like \"from\": \"09:00\", \"to\": \"17:30\".")
                    return nil
                }
                guard let minutes = ConfigFile.minutes(text) else { error(field, "“\(text)” isn't a time. Write it like \"09:00\"."); return nil }
                bounds.append(minutes)
            }
            kind = .timeBetween(start: bounds[0], end: bounds[1])
        default:
            kind = template
        }
        for member in node.object ?? [] where !["if", "unless", "text", "from", "to"].contains(member.key) {
            warn(member.node, "“\(member.key)” isn't a condition field; it's ignored.")
        }
        return Condition(kind, negated: negated)
    }
}

private enum ConditionFile {
    static func kind(named name: String) -> Condition.Kind? {
        ConfigFile.conditionNames.first { $0.0 == name }?.1
    }
}

// MARK: - Writing

enum Writer {
    static func value(_ config: MacsBoredConfig) -> JSONValue {
        var members: [(String, JSONValue)] = [
            ("$schema", .string("./" + ConfigFile.schemaName)),
            ("enabled", .bool(config.passthroughEnabled)),
        ]
        if let login = config.openAtLogin { members.append(("openAtLogin", .bool(login))) }
        members.append(("pauseKeys", config.pauseKeys.map { .string($0.text) } ?? .null))
        members.append(("capsLockAsHyper", .bool(config.hyperKeyEnabled)))
        members.append(("passthrough", .array(config.profiles.map(profile))))
        members.append(("triggers", .array(config.triggers.map(trigger))))
        members.append(("setupCompleted", .bool(config.setupCompleted)))
        return .object(members + config.extra.members)
    }

    static func profile(_ p: PassthroughProfile) -> JSONValue {
        var members: [(String, JSONValue)] = [("name", .string(p.name))]
        if !p.isEnabled { members.append(("enabled", .bool(false))) }
        members.append(("apps", .array(p.apps.map { .string($0.bundleID) })))
        members.append(("shortcuts", .array(SystemShortcutGroup.allCases.filter(p.systemShortcuts.contains).map { .string($0.rawValue) })))
        members.append(("sendEveryKey", .bool(p.captureAllKeys)))
        members.append(("modifiers", .string(p.modifierLayout.rawValue)))
        if let when = conditions(p.conditions) { members.append(("when", when)) }
        return .object(members + p.extra.members)
    }

    static func trigger(_ t: Trigger) -> JSONValue {
        var members: [(String, JSONValue)] = [
            ("name", .string(t.name)),
            ("keys", t.keys.isEmpty ? .null : t.keys.count == 1 ? .string(t.keys[0].text) : .array(t.keys.map { .string($0.text) })),
        ]
        if !t.isEnabled { members.append(("enabled", .bool(false))) }
        members.append(("action", action(t.action)))
        if !t.apps.isEmpty { members.append(("apps", .array(t.apps.map { .string($0.bundleID) }))) }
        if let when = conditions(t.conditions) { members.append(("when", when)) }
        return .object(members + t.extra.members)
    }

    static func action(_ action: TriggerAction) -> JSONValue {
        let value: JSONValue = switch action {
        case let .sendKeys(keys): .string(keys.text)
        case let .openApp(app): .string(app.bundleID)
        case let .runShortcut(name): .string(name)
        case .passThrough: .bool(true)
        case let .open(target): .string(target)
        }
        return .object([(action.kind.rawValue, value)])
    }

    static func conditions(_ set: ConditionSet) -> JSONValue? {
        guard !set.conditions.isEmpty else { return nil }
        let items = JSONValue.array(set.conditions.map(condition))
        return set.match == .all ? items : .object([(set.match.rawValue, items)])
    }

    static func condition(_ c: Condition) -> JSONValue {
        var members: [(String, JSONValue)] = [(c.negated ? "unless" : "if", .string(ConfigFile.name(of: c.kind)))]
        switch c.kind {
        case let .windowTitleContains(text): members.append(("text", .string(text)))
        case let .timeBetween(start, end):
            members.append(("from", .string(ConfigFile.clock(start))))
            members.append(("to", .string(ConfigFile.clock(end))))
        default: break
        }
        return .object(members)
    }
}

// MARK: - The first version's file

/// MacsKeyBored's file (Swift's own encoding of the first version's types), converted once.
enum LegacyConfig {
    static func isLegacy(_ node: JSONNode) -> Bool {
        node["passthrough"] == nil && (node["profiles"] != nil || node["passthroughEnabled"] != nil || node["hyperKeyEnabled"] != nil)
    }

    static func convert(_ node: JSONNode, issues: inout [ConfigFile.Issue]) -> MacsBoredConfig {
        var config = MacsBoredConfig()
        config.passthroughEnabled = node["passthroughEnabled"]?.bool ?? true
        config.hyperKeyEnabled = node["hyperKeyEnabled"]?.bool ?? false
        config.setupCompleted = node["setupCompleted"]?.bool ?? false
        if let field = node["pauseKeys"] { config.pauseKeys = field.isNull ? nil : keys(field) ?? MacsBoredConfig.defaultPauseKeys }
        for item in node["profiles"]?.array ?? [] {
            let apps = (item["apps"]?.array ?? []).compactMap(app)
            guard !apps.isEmpty else { continue }
            let groups = (item["systemShortcuts"]?.array ?? []).compactMap { $0.string.flatMap(SystemShortcutGroup.init(rawValue:)) }
            config.profiles.append(PassthroughProfile(
                name: item["name"]?.string ?? apps[0].name,
                isEnabled: item["isEnabled"]?.bool ?? true,
                apps: apps,
                conditions: conditions(item["conditions"]),
                systemShortcuts: item["systemShortcuts"] == nil ? SystemShortcutGroup.defaultSet : Set(groups),
                captureAllKeys: item["captureAllKeys"]?.bool ?? false,
                modifierLayout: item["modifierLayout"]?.string.flatMap(ModifierLayout.init(rawValue:)) ?? .asIs))
        }
        for item in node["triggers"]?.array ?? [] {
            let name = item["name"]?.string ?? "Trigger"
            guard let actionNode = item["action"], let (kind, payload) = actionNode.object?.first.map({ ($0.key, $0.node["_0"]) }) else { continue }
            let action: TriggerAction?
            switch kind {
            case "sendShortcut": action = payload.flatMap(keys).map { .sendKeys($0) }
            case "openApp": action = payload.flatMap(app).map { .openApp($0) }
            case "openURL": action = payload?.string.map { .open($0) }
            default:
                let what = ["runShell": "ran a shell command", "typeText": "typed text", "togglePause": "paused passthrough",
                            "toggleKeepAwake": "kept the Mac awake"][kind] ?? "did something"
                issues.append(.init(line: nil, message: "“\(name)” \(what), which MacsBored no longer does, so it was left out.",
                                    isWarning: true))
                action = nil
            }
            guard let action else { continue }
            config.triggers.append(Trigger(name: name, isEnabled: item["isEnabled"]?.bool ?? true,
                                           keys: item["shortcut"].flatMap(keys).map { [$0] } ?? [], action: action,
                                           apps: (item["apps"]?.array ?? []).compactMap(app),
                                           conditions: conditions(item["conditions"])))
        }
        return config
    }

    private static func keys(_ node: JSONNode) -> KeyCombo? {
        guard case let .number(code)? = node["keyCode"]?.kind else { return nil }
        var bits: UInt32 = 0
        if case let .number(raw)? = node["modifiers"]?.kind { bits = UInt32(raw) }
        return KeyCombo(keyCode: UInt16(code), modifiers: KeyCombo.Modifiers(rawValue: bits))
    }

    private static func app(_ node: JSONNode) -> AppRef? {
        guard let id = node["bundleID"]?.string else { return nil }
        return AppRef(bundleID: id, name: node["name"]?.string ?? id)
    }

    private static func conditions(_ node: JSONNode?) -> ConditionSet {
        guard let node else { return ConditionSet() }
        let match = node["match"]?.string.flatMap(ConditionMatch.init(rawValue:)) ?? .all
        let items: [Condition] = (node["conditions"]?.array ?? []).compactMap { item in
            guard let member = item["kind"]?.object?.first else { return nil }
            let negated = item["negated"]?.bool ?? false
            let kind: Condition.Kind?
            switch member.key {
            case "windowTitleContains": kind = .windowTitleContains(member.node["_0"]?.string ?? "")
            case "timeBetween":
                if case let .number(s)? = member.node["start"]?.kind, case let .number(e)? = member.node["end"]?.kind {
                    kind = .timeBetween(start: Int(s), end: Int(e))
                } else { kind = nil }
            default: kind = ConditionFile.kind(named: member.key)
            }
            return kind.map { Condition($0, negated: negated) }
        }
        return ConditionSet(match: match, conditions: items)
    }
}
