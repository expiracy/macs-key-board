import XCTest
@testable import MacsBoredCore

/// Keys as the config file writes them: "ctrl+opt+cmd+P", or the menu's "⌃⌥⌘P".
final class KeyTextTests: XCTestCase {
    func testWordsJoinedByPlus() {
        XCTAssertEqual(KeyCombo(text: "ctrl+opt+cmd+P"), KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command]))
        XCTAssertEqual(KeyCombo(text: "Control + Option + Command + p"),
                       KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command]))
        XCTAssertEqual(KeyCombo(text: "cmd+space"), KeyCombo(keyCode: KeyCombo.Code.space, modifiers: .command))
        XCTAssertEqual(KeyCombo(text: "shift+cmd+4"), KeyCombo(keyCode: 21, modifiers: [.shift, .command]))
        XCTAssertEqual(KeyCombo(text: "alt+tab"), KeyCombo(keyCode: KeyCombo.Code.tab, modifiers: .option))
        XCTAssertEqual(KeyCombo(text: "hyper+N"), KeyCombo(keyCode: 45, modifiers: .hyper))
        XCTAssertEqual(KeyCombo(text: "F18"), KeyCombo(keyCode: KeyCombo.Code.f18, modifiers: []))
        XCTAssertEqual(KeyCombo(text: "ctrl+left"), KeyCombo(keyCode: 123, modifiers: .control))
        XCTAssertEqual(KeyCombo(text: "cmd+/"), KeyCombo(keyCode: 44, modifiers: .command))
    }

    func testTheMenusSymbols() {
        XCTAssertEqual(KeyCombo(text: "⌃⌥⌘P"), KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command]))
        XCTAssertEqual(KeyCombo(text: "⌘Space"), KeyCombo(keyCode: KeyCombo.Code.space, modifiers: .command))
        XCTAssertEqual(KeyCombo(text: "⌘⇥"), KeyCombo(keyCode: KeyCombo.Code.tab, modifiers: .command))
        XCTAssertEqual(KeyCombo(text: "⇧⌘4"), KeyCombo(keyCode: 21, modifiers: [.shift, .command]))
        XCTAssertEqual(KeyCombo(text: "⌃←"), KeyCombo(keyCode: 123, modifiers: .control))
    }

    func testNonsenseIsNotAKey() {
        XCTAssertNil(KeyCombo(text: ""))
        XCTAssertNil(KeyCombo(text: "ctrl+banana"))
        XCTAssertNil(KeyCombo(text: "ctrl+opt"))
        XCTAssertNil(KeyCombo(text: "cmd+P+Q"))
        XCTAssertNil(KeyCombo(text: "⌘"))
    }

    func testWrittenOutInOneOrder() {
        XCTAssertEqual(KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.command, .option, .control]).text, "ctrl+opt+cmd+P")
        XCTAssertEqual(KeyCombo(keyCode: KeyCombo.Code.space, modifiers: .command).text, "cmd+space")
        XCTAssertEqual(KeyCombo(keyCode: 21, modifiers: [.shift, .command]).text, "shift+cmd+4")
        XCTAssertEqual(KeyCombo(keyCode: 45, modifiers: .hyper).text, "hyper+N")
        XCTAssertEqual(KeyCombo(keyCode: 123, modifiers: .control).text, "ctrl+left")
        XCTAssertEqual(KeyCombo(keyCode: KeyCombo.Code.f18, modifiers: []).text, "F18")
    }

    func testEveryKeyWrittenReadsBack() {
        for code in UInt16(0)...UInt16(127) {
            let keys = KeyCombo(keyCode: code, modifiers: [.control, .shift])
            XCTAssertEqual(KeyCombo(text: keys.text), keys, keys.text)
        }
    }
}
