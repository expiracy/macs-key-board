import Foundation

/// Everything MacsKeyBored keeps: the passthrough profiles, your triggers and the general switches.
public struct MacsKeyBoredConfig: Codable, Equatable, Sendable {
    /// The main switch: passthrough as a whole.
    public var passthroughEnabled: Bool = true
    public var profiles: [PassthroughProfile] = []
    public var triggers: [Trigger] = []
    /// Pauses passthrough from inside a passthrough app, so ⌘⇥ and the rest work again; nil for none.
    public var pauseKeys: KeyCombo? = MacsKeyBoredConfig.defaultPauseKeys
    /// Caps Lock becomes Hyper (⌃⌥⇧⌘ held together).
    public var hyperKeyEnabled = false
    public var keepAwake = false
    public var setupCompleted = false

    public static let defaultPauseKeys = KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command])

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case passthroughEnabled, profiles, triggers, pauseKeys, hyperKeyEnabled, keepAwake, setupCompleted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MacsKeyBoredConfig()
        passthroughEnabled = (try? c.decode(Bool.self, forKey: .passthroughEnabled)) ?? defaults.passthroughEnabled
        profiles = (try? c.decode(LossyArray<PassthroughProfile>.self, forKey: .profiles))?.elements ?? []
        triggers = (try? c.decode(LossyArray<Trigger>.self, forKey: .triggers))?.elements ?? []
        // Present and null means "no pause keys"; absent means the default.
        if c.contains(.pauseKeys) {
            pauseKeys = try? c.decode(KeyCombo?.self, forKey: .pauseKeys)
        } else {
            pauseKeys = defaults.pauseKeys
        }
        hyperKeyEnabled = (try? c.decode(Bool.self, forKey: .hyperKeyEnabled)) ?? false
        keepAwake = (try? c.decode(Bool.self, forKey: .keepAwake)) ?? false
        setupCompleted = (try? c.decode(Bool.self, forKey: .setupCompleted)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(passthroughEnabled, forKey: .passthroughEnabled)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(triggers, forKey: .triggers)
        try c.encode(pauseKeys, forKey: .pauseKeys)
        try c.encode(hyperKeyEnabled, forKey: .hyperKeyEnabled)
        try c.encode(keepAwake, forKey: .keepAwake)
        try c.encode(setupCompleted, forKey: .setupCompleted)
    }
}

/// The config as a JSON file: read once at launch, written whole on every change.
public final class MacsKeyBoredConfigStore {
    public let url: URL
    public private(set) var config: MacsKeyBoredConfig

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(MacsKeyBoredConfig.self, from: data) {
            self.config = config
        } else {
            self.config = MacsKeyBoredConfig()
        }
    }

    public func save(_ config: MacsKeyBoredConfig) throws {
        self.config = config
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

public enum MacsKeyBoredPaths {
    /// `~/Library/Application Support/MacsKeyBored/config.json`.
    public static func configURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MacsKeyBored", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}
