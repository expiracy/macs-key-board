import XCTest
@testable import MacsBoredCore

/// The file on disk: found, watched, and never written over while it has a mistake.
final class ConfigStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var url: URL { folder.appendingPathComponent("config.json") }

    private func put(_ text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func onDisk() throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testWithNoFileTheDefaultsAreWrittenWithTheSchemaBeside() throws {
        let store = MacsBoredConfigStore(url: url)
        XCTAssertEqual(store.config, MacsBoredConfig())
        XCTAssertEqual(try onDisk(), ConfigFile.written(MacsBoredConfig()))
        XCTAssertEqual(try String(contentsOf: store.schemaURL, encoding: .utf8), ConfigSchema.text)
    }

    func testTheFirstVersionsFileIsConvertedOnce() throws {
        let legacy = folder.appendingPathComponent("old.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"passthroughEnabled": false, "hyperKeyEnabled": true, "profiles": [], "triggers": []}"#.utf8).write(to: legacy)
        let store = MacsBoredConfigStore(url: url, legacyURL: legacy)
        XCTAssertFalse(store.config.passthroughEnabled)
        XCTAssertTrue(store.config.hyperKeyEnabled)
        XCTAssertTrue(try onDisk().contains(#""capsLockAsHyper": true"#))
    }

    func testWhatIsSavedIsReadBack() throws {
        let store = MacsBoredConfigStore(url: url)
        var config = store.config
        config.triggers = [Trigger(name: "Notes", keys: [KeyCombo(text: "ctrl+opt+N")!],
                                   action: .openApp(AppRef(bundleID: "com.apple.Notes", name: "Notes")))]
        try store.save(config)
        XCTAssertEqual(MacsBoredConfigStore(url: url).config.triggers.map(\.action),
                       [.openApp(AppRef(bundleID: "com.apple.Notes", name: "com.apple.Notes"))])
    }

    func testAnEditOnDiskIsPickedUpAndKeepsEntriesIDs() throws {
        try put(#"{"triggers": [{"name": "A", "keys": "cmd+1", "action": {"passThrough": true}}]}"#)
        let store = MacsBoredConfigStore(url: url)
        let id = try XCTUnwrap(store.config.triggers.first?.id)
        XCTAssertFalse(store.reload(), "nothing changed")
        try put(#"{"triggers": [{"name": "A", "keys": "cmd+2", "action": {"passThrough": true}}, {"name": "B", "action": {"open": "x"}}]}"#)
        XCTAssertTrue(store.reload())
        XCTAssertEqual(store.config.triggers.map(\.keys), [[KeyCombo(text: "cmd+2")!], []])
        XCTAssertEqual(store.config.triggers.first?.id, id)
    }

    func testAMistakeOnDiskKeepsTheLastGoodSettingsAndBlocksSaving() throws {
        try put(#"{"enabled": false}"#)
        let store = MacsBoredConfigStore(url: url)
        let broken = "{\n  \"enabled\": nope\n}"
        try put(broken)
        XCTAssertTrue(store.reload())
        XCTAssertFalse(store.config.passthroughEnabled, "the last good settings")
        XCTAssertEqual(store.errors.map(\.line), [2])
        XCTAssertThrowsError(try store.save(MacsBoredConfig()))
        XCTAssertEqual(try onDisk(), broken, "the hand edit is left alone")

        try put(#"{"enabled": true}"#)
        XCTAssertTrue(store.reload())
        XCTAssertTrue(store.config.passthroughEnabled)
        XCTAssertEqual(store.issues, [])
    }

    func testSavingFirstTakesInAnEditNotYetReloaded() throws {
        let store = MacsBoredConfigStore(url: url)
        try put("{\n  \"enabled\": oops\n}")
        XCTAssertThrowsError(try store.save(MacsBoredConfig()), "an edit on disk with a mistake is never overwritten")
    }
}
