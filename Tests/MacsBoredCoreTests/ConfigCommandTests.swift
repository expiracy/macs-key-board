import XCTest
@testable import MacsBoredCore

/// `macsbored check` and `macsbored path`, for scripts and agents.
final class ConfigCommandTests: XCTestCase {
    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: file) }

    private func run(_ args: [String]) -> ConfigCommand.Outcome? {
        ConfigCommand.run(args, defaultURL: file)
    }

    func testAppArgumentsAreNotCommands() {
        XCTAssertNil(run([]))
        XCTAssertNil(run(["--open-menu"]))
    }

    func testPathPrintsWhereTheFileIs() {
        XCTAssertEqual(run(["path"]), .init(output: file.path, status: 0))
    }

    func testCheckPassesAGoodFile() throws {
        try Data(#"{"triggers": [{"keys": "cmd+1", "action": {"passThrough": true}}]}"#.utf8).write(to: file)
        XCTAssertEqual(run(["check"]), .init(output: "\(file.path): no problems.", status: 0))
    }

    func testCheckListsEachMistakeWithItsLineAndFails() throws {
        try Data("{\n  \"enabled\": \"yes\",\n  \"theme\": 1\n}".utf8).write(to: file)
        XCTAssertEqual(run(["check", file.path]), .init(output: """
        \(file.path):2: error: “enabled” should be true or false.
        \(file.path):3: warning: “theme” isn't a MacsBored setting; it's kept as it is.
        """, status: 1))
    }

    func testCheckFailsWhenThereIsNoFile() {
        XCTAssertEqual(run(["check"])?.status, 1)
    }

    func testSchemaPrintsTheSchema() {
        XCTAssertEqual(run(["schema"]), .init(output: ConfigSchema.text, status: 0))
    }
}
