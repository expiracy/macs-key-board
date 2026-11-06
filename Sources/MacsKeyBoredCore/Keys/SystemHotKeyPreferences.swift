import Foundation

/// Whether a system hot key is on, as System Settings records it (`com.apple.symbolichotkeys`), for
/// when the WindowServer can't be asked directly. A hot key that was never changed may not be written
/// down at all: those count as on only if macOS ships them on, so passthrough never claims, and later
/// switches on, a shortcut that was off.
public enum SystemHotKeyPreferences {
    /// Hot keys macOS ships switched on that it doesn't record until they're changed: the app
    /// switcher, keyboard navigation and the Help menu's search.
    public static let onWhenUnrecorded: Set<Int> = [1, 2, 6, 27, 7, 8, 9, 10, 11, 12, 13, 57, 98]

    public static func isEnabled(_ id: Int, preferences: [String: Any]) -> Bool {
        guard let entry = preferences[String(id)] as? [String: Any] else { return onWhenUnrecorded.contains(id) }
        if let flag = entry["enabled"] as? Bool { return flag }
        if let number = entry["enabled"] as? NSNumber { return number.intValue != 0 }
        return onWhenUnrecorded.contains(id)
    }
}
