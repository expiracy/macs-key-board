import Foundation

/// The kinds of macOS's own shortcuts a passthrough app can take over, each a handful of the
/// system's "symbolic hot keys" (the ones in System Settings › Keyboard › Keyboard Shortcuts).
/// Switching a group off while the app is in front lets its keys reach the app instead.
public enum SystemShortcutGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case appSwitcher
    case spotlight
    case missionControl
    case spaces
    case screenshots
    case inputSources
    case dockAndCentre
    case keyboardNavigation
    case accessibility
    case helpMenu

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appSwitcher: "App switcher"
        case .spotlight: "Spotlight"
        case .missionControl: "Mission Control"
        case .spaces: "Spaces"
        case .screenshots: "Screenshots"
        case .inputSources: "Input sources"
        case .dockAndCentre: "Dock, Launchpad and Notification Centre"
        case .keyboardNavigation: "Keyboard navigation"
        case .accessibility: "Zoom and contrast"
        case .helpMenu: "Help menu search"
        }
    }

    /// The keys, as a reminder of what goes to the app instead ("⌘⇥, ⌘`").
    public var keys: String {
        switch self {
        case .appSwitcher: "⌘⇥  ⌘⇧⇥  ⌘`"
        case .spotlight: "⌘Space  ⌥⌘Space"
        case .missionControl: "⌃↑  ⌃↓  F3  F11"
        case .spaces: "⌃←  ⌃→  ⌃1…9"
        case .screenshots: "⇧⌘3  ⇧⌘4  ⇧⌘5"
        case .inputSources: "⌃Space  ⌃⌥Space"
        case .dockAndCentre: "⌥⌘D  Launchpad  Notifications"
        case .keyboardNavigation: "⌃F1…⌃F8"
        case .accessibility: "⌥⌘8  ⌥⌘=  ⌥⌘-"
        case .helpMenu: "⇧⌘/"
        }
    }

    /// What a Windows session usually uses these keys for, so the choice reads as a trade.
    public var windowsMeaning: String {
        switch self {
        case .appSwitcher: "Win+Tab and Alt+Tab in the session"
        case .spotlight: "Win+Space and the Start menu"
        case .missionControl: "Ctrl+arrows and F3/F11 in apps"
        case .spaces: "Ctrl+← → word jumps, Ctrl+1…9 tabs"
        case .screenshots: "Win+Shift+S style captures in the session"
        case .inputSources: "Ctrl+Space in editors and Excel"
        case .dockAndCentre: "Win+Alt+D and friends"
        case .keyboardNavigation: "Ctrl+F-keys in Windows apps"
        case .accessibility: "Win+= and Win+- magnifier"
        case .helpMenu: "Ctrl+Shift+/ in apps"
        }
    }

    public var symbol: String {
        switch self {
        case .appSwitcher: "square.stack"
        case .spotlight: "magnifyingglass"
        case .missionControl: "rectangle.3.group"
        case .spaces: "rectangle.split.3x1"
        case .screenshots: "camera.viewfinder"
        case .inputSources: "globe"
        case .dockAndCentre: "dock.rectangle"
        case .keyboardNavigation: "keyboard"
        case .accessibility: "plus.magnifyingglass"
        case .helpMenu: "questionmark.circle"
        }
    }

    /// The symbolic hot key numbers in the group, as `com.apple.symbolichotkeys` numbers them.
    public var hotKeyIDs: [Int] {
        switch self {
        case .appSwitcher: [1, 2, 6, 27]
        case .spotlight: [64, 65]
        case .missionControl: [32, 33, 34, 35, 36, 37]
        case .spaces: [79, 80, 81, 82] + Array(118...126)
        case .screenshots: [28, 29, 30, 31, 184]
        case .inputSources: [60, 61]
        case .dockAndCentre: [52, 160, 163, 175]
        case .keyboardNavigation: [7, 8, 9, 10, 11, 12, 13, 57]
        case .accessibility: [15, 17, 19, 21, 25, 26]
        case .helpMenu: [98]
        }
    }

    /// What a new passthrough profile takes over: everything a Windows session expects, leaving
    /// the accessibility shortcuts (which some people rely on everywhere) with macOS.
    public static let defaultSet: Set<SystemShortcutGroup> = Set(allCases).subtracting([.accessibility])
}

extension Set where Element == SystemShortcutGroup {
    /// Every hot key number in these groups.
    public var hotKeyIDs: Set<Int> { Set<Int>(flatMap { $0.hotKeyIDs }) }
}
