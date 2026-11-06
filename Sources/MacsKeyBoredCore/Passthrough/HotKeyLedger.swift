import Foundation

/// The system hot keys to switch off and back on, in one step.
public struct HotKeyChanges: Equatable, Sendable {
    public var disable: Set<Int>
    public var enable: Set<Int>

    public init(disable: Set<Int>, enable: Set<Int>) {
        self.disable = disable
        self.enable = enable
    }

    public var isEmpty: Bool { disable.isEmpty && enable.isEmpty }
}

/// Which system hot keys this app has switched off, so it only ever switches those back on.
public struct HotKeyLedger: Equatable, Sendable {
    public private(set) var disabledByUs: Set<Int>

    public init(disabledByUs: Set<Int> = []) {
        self.disabledByUs = disabledByUs
    }

    /// The changes that leave `wanted` switched off: hot keys already off (by you, in System Settings)
    /// are left alone and never claimed, and ones this app switched off but no longer wants go back on.
    public mutating func move(to wanted: Set<Int>, isEnabled: (Int) -> Bool) -> HotKeyChanges {
        let release = disabledByUs.subtracting(wanted)
        let claim = wanted.subtracting(disabledByUs).filter(isEnabled)
        disabledByUs = disabledByUs.subtracting(release).union(claim)
        return HotKeyChanges(disable: claim, enable: release)
    }

    /// Everything this app switched off goes back on (quitting, pausing, or a ledger left by a crash).
    public mutating func restoreAll() -> HotKeyChanges {
        let release = disabledByUs
        disabledByUs = []
        return HotKeyChanges(disable: [], enable: release)
    }
}
