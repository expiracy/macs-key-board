import XCTest
@testable import MacsBoredCore

final class SystemHotKeyPreferencesTests: XCTestCase {
    /// Shaped as `com.apple.symbolichotkeys` › AppleSymbolicHotKeys reads back from UserDefaults.
    private let preferences: [String: Any] = [
        "64": ["enabled": 1, "value": ["parameters": [32, 49, 1_048_576]]],   // ⌘Space, on
        "65": ["enabled": 0],                                               // Finder search, switched off
        "15": ["enabled": false],                                           // Zoom, off
        "79": ["enabled": true],
    ]

    func testARecordedHotKeyIsWhatTheRecordSays() {
        XCTAssertTrue(SystemHotKeyPreferences.isEnabled(64, preferences: preferences))
        XCTAssertTrue(SystemHotKeyPreferences.isEnabled(79, preferences: preferences))
        XCTAssertFalse(SystemHotKeyPreferences.isEnabled(65, preferences: preferences))
        XCTAssertFalse(SystemHotKeyPreferences.isEnabled(15, preferences: preferences))
    }

    func testAnUnrecordedHotKeyIsOnOnlyIfMacOSShipsItOn() {
        // ⌘⇥ is never written down: it is always on.
        XCTAssertTrue(SystemHotKeyPreferences.isEnabled(1, preferences: preferences))
        XCTAssertTrue(SystemHotKeyPreferences.isEnabled(98, preferences: preferences))
        // "Switch to Desktop 9" unrecorded means it was never switched on.
        XCTAssertFalse(SystemHotKeyPreferences.isEnabled(126, preferences: preferences))
        XCTAssertFalse(SystemHotKeyPreferences.isEnabled(15, preferences: [:]))
    }
}
