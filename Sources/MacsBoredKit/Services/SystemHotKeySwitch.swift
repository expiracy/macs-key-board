#if canImport(AppKit)
import Foundation
import MacsBoredCore

/// The WindowServer's own switch for macOS's system shortcuts ("symbolic hot keys": ⌘⇥, ⌘Space,
/// ⌃←…). It is private API, the one AltTab uses to take over ⌘⇥, so it is looked up at run time and
/// passthrough says so if it is missing rather than failing to launch.
enum SymbolicHotKeys {
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private typealias IsEnabled = @convention(c) (Int32) -> Bool

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        ?? dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    private static let setFunction: SetEnabled? = symbol("CGSSetSymbolicHotKeyEnabled")
    private static let isFunction: IsEnabled? = symbol("CGSIsSymbolicHotKeyEnabled")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var isAvailable: Bool { setFunction != nil }

    /// On macOS 26 the WindowServer's own answer reads every hot key as off, ⌘⇥ included. When it
    /// says that about all of them, it isn't believed and System Settings' record is read instead.
    private static let askWindowServer: Bool = {
        guard let isFunction else { return false }
        return SystemShortcutGroup.allCases.flatMap(\.hotKeyIDs).contains { isFunction(Int32($0)) }
    }()

    static func isEnabled(_ id: Int) -> Bool {
        if askWindowServer, let isFunction { return isFunction(Int32(id)) }
        let preferences = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        return SystemHotKeyPreferences.isEnabled(id, preferences: preferences)
    }

    static func set(_ id: Int, enabled: Bool) {
        _ = setFunction?(Int32(id), enabled)
    }
}

/// Switches system shortcuts off and back on for passthrough, and keeps the ledger of which ones it
/// switched off on disk, written before each change, so a crash or a force quit is undone on the next launch.
final class SystemHotKeySwitch {
    private static let defaultsKey = "MacsBored.hotKeysDisabledByUs"
    private var ledger: HotKeyLedger
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.array(forKey: Self.defaultsKey) as? [Int] ?? []
        ledger = HotKeyLedger(disabledByUs: Set(saved))
    }

    var disabledCount: Int { ledger.disabledByUs.count }

    /// Puts back anything a previous run left switched off.
    func restoreLeftovers() {
        apply(ledger.restoreAll())
    }

    func move(to wanted: Set<Int>) {
        guard SymbolicHotKeys.isAvailable else { return }
        apply(ledger.move(to: wanted, isEnabled: SymbolicHotKeys.isEnabled))
    }

    func restoreAll() {
        apply(ledger.restoreAll())
    }

    private func apply(_ changes: HotKeyChanges) {
        guard !changes.isEmpty else { return }
        // The ledger reaches the disk first: if we die between here and the switch, the next launch
        // turns back on at worst one that was never turned off, which is harmless.
        defaults.set(ledger.disabledByUs.union(changes.enable).sorted(), forKey: Self.defaultsKey)
        defaults.synchronize()
        for id in changes.disable { SymbolicHotKeys.set(id, enabled: false) }
        for id in changes.enable { SymbolicHotKeys.set(id, enabled: true) }
        defaults.set(ledger.disabledByUs.sorted(), forKey: Self.defaultsKey)
    }
}
#endif
