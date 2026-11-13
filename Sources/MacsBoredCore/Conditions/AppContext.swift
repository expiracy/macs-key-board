import Foundation

/// What is true right now, as far as conditions care: the app in front and its focused window, the
/// displays, the power source, the time and Caps Lock. The app reads it a few times a second; every
/// decision is made from one of these, so the decisions can be tested without a screen.
public struct AppContext: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var processID: Int32?
    /// The focused window's title, when Accessibility can read it.
    public var windowTitle: String?
    /// The focused window is in macOS full screen (its own space).
    public var isFullScreen: Bool
    /// The focused window covers its whole display, full screen or not.
    public var fillsScreen: Bool
    public var displayCount: Int
    /// A display other than the Mac's own is connected.
    public var hasExternalDisplay: Bool
    public var onBattery: Bool
    /// Minutes since local midnight, 0…1439.
    public var minuteOfDay: Int
    public var capsLockOn: Bool

    public init(bundleID: String? = nil, appName: String? = nil, processID: Int32? = nil,
                windowTitle: String? = nil, isFullScreen: Bool = false, fillsScreen: Bool = false,
                displayCount: Int = 1, hasExternalDisplay: Bool = false, onBattery: Bool = false,
                minuteOfDay: Int = 12 * 60, capsLockOn: Bool = false) {
        self.bundleID = bundleID
        self.appName = appName
        self.processID = processID
        self.windowTitle = windowTitle
        self.isFullScreen = isFullScreen
        self.fillsScreen = fillsScreen
        self.displayCount = displayCount
        self.hasExternalDisplay = hasExternalDisplay
        self.onBattery = onBattery
        self.minuteOfDay = minuteOfDay
        self.capsLockOn = capsLockOn
    }
}
