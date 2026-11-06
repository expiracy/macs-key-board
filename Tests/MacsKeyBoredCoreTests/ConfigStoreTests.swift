import XCTest
@testable import MacsKeyBoredCore

final class ConfigStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macskeybored-\(UUID().uuidString).json")
    }

    func testAMissingFileGivesTheDefaults() {
        let store = MacsKeyBoredConfigStore(url: tempURL())
        XCTAssertEqual(store.config, MacsKeyBoredConfig())
        XCTAssertTrue(store.config.passthroughEnabled)
        XCTAssertEqual(store.config.pauseKeys, KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command]))
    }

    func testWhatIsSavedIsReadBack() throws {
        let url = tempURL()
        let store = MacsKeyBoredConfigStore(url: url)
        var config = MacsKeyBoredConfig()
        config.profiles = [PassthroughProfile(
            name: "Citrix", apps: [AppRef(bundleID: "com.citrix.receiver.icaviewer.mac", name: "Citrix Viewer")],
            conditions: ConditionSet(match: .any, conditions: [Condition(.fullScreen),
                                                               Condition(.windowTitleContains("Desktop"), negated: true),
                                                               Condition(.timeBetween(start: 60, end: 120))]),
            systemShortcuts: [.spotlight, .spaces], captureAllKeys: false, modifierLayout: .swapCommandControl)]
        config.triggers = [Trigger(name: "Snippet", shortcut: KeyCombo(keyCode: 17, modifiers: .hyper, character: "t"),
                                   action: .typeText("Kind regards"), apps: [AppRef(bundleID: "a", name: "A")])]
        config.hyperKeyEnabled = true
        config.pauseKeys = nil
        try store.save(config)
        XCTAssertEqual(MacsKeyBoredConfigStore(url: url).config, config)
    }

    func testOneBadEntryCostsOnlyItself() throws {
        let url = tempURL()
        let good = UUID()
        let json = """
        {"passthroughEnabled": false,
         "profiles": [
           {"id": "\(good.uuidString)", "name": "Windows", "apps": [{"bundleID": "com.microsoft.rdc.macos", "name": "Windows App"}],
            "systemShortcuts": ["appSwitcher", "somethingFromTheFuture"]},
           {"name": "no id"}
         ],
         "triggers": [{"id": "\(UUID().uuidString)", "name": "x", "action": {"teleport": {}}}]}
        """
        try Data(json.utf8).write(to: url)
        let config = MacsKeyBoredConfigStore(url: url).config
        XCTAssertFalse(config.passthroughEnabled)
        XCTAssertEqual(config.profiles.map(\.id), [good])
        XCTAssertEqual(config.profiles.first?.systemShortcuts, [.appSwitcher])
        XCTAssertEqual(config.triggers, [])
    }
}
