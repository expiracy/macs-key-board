import Foundation

/// Everything MacsBored keeps: the passthrough entries, your triggers and the general switches.
/// It lives in `config.json` (see `ConfigFile` for the format).
public struct MacsBoredConfig: Equatable, Sendable {
    /// The main switch: passthrough as a whole.
    public var passthroughEnabled = true
    /// Whether MacsBored opens at login; nil leaves it as macOS has it.
    public var openAtLogin: Bool?
    public var profiles: [PassthroughProfile] = []
    public var triggers: [Trigger] = []
    /// Pauses passthrough from inside a passthrough app, so ⌘⇥ and the rest work again; nil for none.
    public var pauseKeys: KeyCombo? = MacsBoredConfig.defaultPauseKeys
    /// Caps Lock becomes Hyper (⌃⌥⇧⌘ held together).
    public var hyperKeyEnabled = false
    public var setupCompleted = false
    /// Top-level fields MacsBored doesn't know, written back as they were.
    public var extra = JSONFields()

    public static let defaultPauseKeys = KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command])

    public init() {}

    /// This config with each entry keeping the ID it has in `previous` when it is plainly the same
    /// entry (the same name, or the same place with no other claim), so a reload from disk doesn't
    /// pull an open editor's entry out from under it.
    public func keepingIDs(of previous: MacsBoredConfig) -> MacsBoredConfig {
        var next = self
        next.profiles = Self.matched(profiles, previous.profiles, name: \.name) { $0.id = $1 }
        next.triggers = Self.matched(triggers, previous.triggers, name: \.name) { $0.id = $1 }
        return next
    }

    private static func matched<T: Identifiable>(_ items: [T], _ old: [T], name: KeyPath<T, String>,
                                                 setID: (inout T, T.ID) -> Void) -> [T] where T.ID == UUID {
        var unused = old
        var out = items
        for index in out.indices {
            if let match = unused.firstIndex(where: { $0[keyPath: name] == out[index][keyPath: name] }) {
                setID(&out[index], unused.remove(at: match).id)
            } else if index < old.count, let spare = unused.firstIndex(where: { $0.id == old[index].id }),
                      !items.contains(where: { $0[keyPath: name] == old[index][keyPath: name] }) {
                setID(&out[index], unused.remove(at: spare).id)
            }
        }
        return out
    }
}

/// The settings file on disk. It holds the last good settings: when the file has a mistake, those
/// keep running, `issues` says what's wrong, and nothing is written over the file until it's fixed.
public final class MacsBoredConfigStore {
    public enum SaveError: Error, Equatable {
        /// The file on disk has a mistake; writing would throw away the hand edit.
        case fileHasMistakes([ConfigFile.Issue])
    }

    public let url: URL
    public private(set) var config: MacsBoredConfig
    /// What's wrong with the file as it is on disk now, errors and warnings.
    public private(set) var issues: [ConfigFile.Issue] = []
    /// The bytes last read or written, so the store's own writes and unchanged files aren't re-read.
    private var lastData: Data?

    public var errors: [ConfigFile.Issue] { issues.filter { !$0.isWarning } }
    public var schemaURL: URL { url.deletingLastPathComponent().appendingPathComponent(ConfigFile.schemaName) }

    /// Reads the file. With none, it takes `legacyURL` (the first version's file) converted, or the
    /// defaults, and writes the file so there's one to find. The schema is written beside it.
    public init(url: URL, legacyURL: URL? = nil) {
        self.url = url
        self.config = MacsBoredConfig()
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(ConfigSchema.text.utf8).write(to: schemaURL, options: .atomic)
        if let data = try? Data(contentsOf: url) {
            apply(data)
        } else {
            if let legacyURL, let data = try? Data(contentsOf: legacyURL) {
                let reading = ConfigFile.read(data)
                if let converted = reading.config { config = converted }
                issues = reading.issues
            }
            try? write(config)
        }
    }

    /// Reads the file again. Returns true when the settings or what's wrong with them changed.
    @discardableResult
    public func reload() -> Bool {
        guard let data = try? Data(contentsOf: url), data != lastData else { return false }
        let before = (config, issues)
        apply(data)
        return before.0 != config || before.1 != issues
    }

    public func save(_ config: MacsBoredConfig) throws {
        reload()
        guard errors.isEmpty else { throw SaveError.fileHasMistakes(errors) }
        try write(config)
    }

    private func apply(_ data: Data) {
        lastData = data
        let reading = ConfigFile.read(data)
        issues = reading.issues
        if let next = reading.config { config = next.keepingIDs(of: config) }
    }

    private func write(_ config: MacsBoredConfig) throws {
        let data = Data(ConfigFile.written(config).utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lastData = data
        self.config = config
        issues = ConfigFile.read(data).issues
    }
}

public enum MacsBoredPaths {
    /// `~/Library/Application Support/MacsBored/config.json`.
    public static func configURL() throws -> URL {
        try supportFolder().appendingPathComponent("MacsBored", isDirectory: true).appendingPathComponent("config.json")
    }

    /// Where the first version, MacsKeyBored, kept its file.
    public static func legacyConfigURL() throws -> URL {
        try supportFolder().appendingPathComponent("MacsKeyBored", isDirectory: true).appendingPathComponent("config.json")
    }

    private static func supportFolder() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
}
