import XCTest
@testable import MacsBoredCore

/// The config file's JSON: read with each value's line, written the way people write it by hand.
final class JSONDocumentTests: XCTestCase {
    func testValuesKeepTheirLineAndKeyOrder() throws {
        let node = try JSONNode.parse("""
        {
          "b": 1,
          "a": [true, null, "x\\n\\u00e9"],
          "c": { "d": -2.5e1 }
        }
        """)
        XCTAssertEqual(node.object?.map(\.key), ["b", "a", "c"])
        XCTAssertEqual(node["a"]?.line, 3)
        XCTAssertEqual(node["a"]?.array?.map(\.value), [.bool(true), .null, .string("x\né")])
        XCTAssertEqual(node["c"]?["d"]?.value, .number(-25))
        XCTAssertEqual(node["c"]?["d"]?.line, 4)
    }

    func testAMistakeNamesItsLine() {
        XCTAssertThrowsError(try JSONNode.parse("{\n  \"a\": 1,\n  \"b\": tru\n}")) { error in
            XCTAssertEqual((error as? JSONParseError)?.line, 3)
        }
        XCTAssertThrowsError(try JSONNode.parse("{\n  \"a\": 1,\n}")) { error in
            XCTAssertEqual((error as? JSONParseError)?.line, 3)
        }
        XCTAssertThrowsError(try JSONNode.parse("{\"a\": 1} 2")) { error in
            XCTAssertEqual((error as? JSONParseError)?.line, 1)
        }
        XCTAssertThrowsError(try JSONNode.parse(""))
    }

    func testWrittenWithShortListsAndObjectsOnOneLine() {
        let value: JSONValue = .object([
            ("name", .string("Open Notes")),
            ("apps", .array([.string("com.apple.finder")])),
            ("action", .object([("openApp", .string("com.apple.Notes"))])),
            ("when", .array([
                .object([("unless", .string("onBattery"))]),
                .object([("if", .string("timeBetween")), ("from", .string("09:00")), ("to", .string("17:30"))]),
            ])),
            ("empty", .array([])),
            ("nested", .object([("list", .array([.number(1), .number(2.5)]))])),
        ])
        XCTAssertEqual(value.written(), """
        {
          "name": "Open Notes",
          "apps": ["com.apple.finder"],
          "action": { "openApp": "com.apple.Notes" },
          "when": [
            { "unless": "onBattery" },
            { "if": "timeBetween", "from": "09:00", "to": "17:30" }
          ],
          "empty": [],
          "nested": {
            "list": [1, 2.5]
          }
        }

        """)
    }

    func testWhatIsWrittenReadsBack() throws {
        let value: JSONValue = .object([
            ("text", .string("quote \" slash \\ tab \t é ⌘")),
            ("list", .array([.bool(false), .null, .number(12), .object([])])),
        ])
        XCTAssertEqual(try JSONNode.parse(value.written()).value, value)
    }
}
