import Foundation

/// One thing that must be true (or, `negated`, must not be) for a profile or trigger to act, in the
/// spirit of BetterTouchTool's conditions.
public struct Condition: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// The window in front is in macOS full screen.
        case fullScreen
        /// The window in front covers its whole display (full screen, or zoomed to fill it).
        case fillsScreen
        /// The window in front's title contains this text, ignoring case.
        case windowTitleContains(String)
        /// A display other than the Mac's own is connected.
        case externalDisplay
        /// The Mac is running on its battery.
        case onBattery
        /// The time is from `start` up to `end`, in minutes since midnight; a range that ends before
        /// it starts runs over midnight.
        case timeBetween(start: Int, end: Int)
        /// Caps Lock is on: a switch you can flip with one key.
        case capsLock
    }

    public var id: UUID
    public var kind: Kind
    public var negated: Bool

    public init(_ kind: Kind, negated: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.negated = negated
    }

    public func isSatisfied(by context: AppContext) -> Bool {
        kind.holds(in: context) != negated
    }
}

extension Condition.Kind {
    func holds(in context: AppContext) -> Bool {
        switch self {
        case .fullScreen:
            return context.isFullScreen
        case .fillsScreen:
            return context.isFullScreen || context.fillsScreen
        case let .windowTitleContains(text):
            let needle = text.trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else { return true }
            return context.windowTitle?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .externalDisplay:
            return context.hasExternalDisplay
        case .onBattery:
            return context.onBattery
        case let .timeBetween(start, end):
            let now = context.minuteOfDay
            if start == end { return true }
            return start < end ? (now >= start && now < end) : (now >= start || now < end)
        case .capsLock:
            return context.capsLockOn
        }
    }

    /// The menu's name for the kind, as a sentence would say it after "When".
    public var title: String {
        switch self {
        case .fullScreen: "Window is full screen"
        case .fillsScreen: "Window fills the screen"
        case .windowTitleContains: "Window title contains"
        case .externalDisplay: "External display connected"
        case .onBattery: "Running on battery"
        case .timeBetween: "Time is between"
        case .capsLock: "Caps Lock is on"
        }
    }

    public var symbol: String {
        switch self {
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .fillsScreen: "rectangle.inset.filled"
        case .windowTitleContains: "textformat"
        case .externalDisplay: "display.2"
        case .onBattery: "battery.50"
        case .timeBetween: "clock"
        case .capsLock: "capslock"
        }
    }

    /// One of each kind, as the editor's Add menu offers them.
    public static let templates: [Condition.Kind] = [
        .fullScreen, .fillsScreen, .windowTitleContains(""), .externalDisplay, .onBattery,
        .timeBetween(start: 9 * 60, end: 17 * 60 + 30), .capsLock,
    ]
}

/// How a list of conditions combine.
public enum ConditionMatch: String, Codable, CaseIterable, Sendable {
    case all
    case any
}

/// A profile's or trigger's conditions: none means always.
public struct ConditionSet: Codable, Hashable, Sendable {
    public var match: ConditionMatch
    public var conditions: [Condition]

    public init(match: ConditionMatch = .all, conditions: [Condition] = []) {
        self.match = match
        self.conditions = conditions
    }

    public func isSatisfied(by context: AppContext) -> Bool {
        guard !conditions.isEmpty else { return true }
        switch match {
        case .all: return conditions.allSatisfy { $0.isSatisfied(by: context) }
        case .any: return conditions.contains { $0.isSatisfied(by: context) }
        }
    }

    private enum CodingKeys: String, CodingKey { case match, conditions }

    /// A condition of a kind this build doesn't know is dropped alone; the rest survive.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = (try? c.decodeIfPresent(ConditionMatch.self, forKey: .match)) ?? .all
        conditions = (try? c.decodeIfPresent(LossyArray<Condition>.self, forKey: .conditions))?.elements ?? []
    }
}
