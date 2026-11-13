import XCTest
@testable import MacsBoredCore

/// The schema beside the file names the same things the file reads.
final class ConfigSchemaTests: XCTestCase {
    private func schema() throws -> JSONNode { try JSONNode.parse(ConfigSchema.text) }

    private func strings(_ node: JSONNode?) -> [String] { (node?.array ?? []).compactMap(\.string) }

    func testItIsJSON() throws {
        XCTAssertEqual(try schema()["title"]?.string, "MacsBored settings")
    }

    func testItListsEveryActionConditionAndShortcutGroup() throws {
        let defs = try XCTUnwrap(try schema()["$defs"])
        XCTAssertEqual(defs["action"]?["properties"]?.object?.map(\.key), TriggerAction.Kind.allCases.map(\.rawValue))
        XCTAssertEqual(strings(defs["condition"]?["properties"]?["if"]?["enum"]), ConfigFile.conditionNames.map(\.0))
        let groups = defs["passthrough"]?["properties"]?["shortcuts"]?["oneOf"]?.array?.first?["items"]?["enum"]
        XCTAssertEqual(strings(groups), SystemShortcutGroup.allCases.map(\.rawValue))
        XCTAssertEqual(strings(defs["passthrough"]?["properties"]?["modifiers"]?["enum"]), ModifierLayout.allCases.map(\.rawValue))
    }

    func testItsExamplesReadWithoutMistakes() throws {
        let defs = try XCTUnwrap(try schema()["$defs"])
        let triggers = (defs["trigger"]?["examples"]?.array ?? []).map(\.value)
        let passthrough = (defs["passthrough"]?["examples"]?.array ?? []).map(\.value)
        let file = JSONValue.object([("passthrough", .array(passthrough)), ("triggers", .array(triggers))]).written()
        XCTAssertEqual(ConfigFile.read(Data(file.utf8)).issues, [])
    }
}
