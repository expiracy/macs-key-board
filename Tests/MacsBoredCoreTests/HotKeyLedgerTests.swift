import XCTest
@testable import MacsBoredCore

final class HotKeyLedgerTests: XCTestCase {
    /// A pretend WindowServer: which hot keys are on now.
    private var enabled: Set<Int> = []

    private func apply(_ changes: HotKeyChanges) {
        enabled.subtract(changes.disable)
        enabled.formUnion(changes.enable)
    }

    func testSwitchesOffWhatIsWantedAndRemembersIt() {
        enabled = [1, 2, 64]
        var ledger = HotKeyLedger()
        let changes = ledger.move(to: [1, 64], isEnabled: enabled.contains)
        XCTAssertEqual(changes, HotKeyChanges(disable: [1, 64], enable: []))
        XCTAssertEqual(ledger.disabledByUs, [1, 64])
    }

    func testNeverTurnsOnAHotKeyYouHadSwitchedOff() {
        enabled = [1]          // 64 (Spotlight) was already off in System Settings
        var ledger = HotKeyLedger()
        apply(ledger.move(to: [1, 64], isEnabled: enabled.contains))
        XCTAssertEqual(ledger.disabledByUs, [1])
        let back = ledger.move(to: [], isEnabled: enabled.contains)
        XCTAssertEqual(back, HotKeyChanges(disable: [], enable: [1]))
        XCTAssertEqual(ledger.disabledByUs, [])
    }

    func testMovingToAnotherProfileOnlyChangesTheDifference() {
        enabled = [1, 2, 64, 79]
        var ledger = HotKeyLedger()
        apply(ledger.move(to: [1, 2, 64], isEnabled: enabled.contains))
        let changes = ledger.move(to: [1, 79], isEnabled: enabled.contains)
        XCTAssertEqual(changes, HotKeyChanges(disable: [79], enable: [2, 64]))
        apply(changes)
        XCTAssertEqual(enabled, [2, 64])
        XCTAssertEqual(ledger.disabledByUs, [1, 79])
    }

    func testStayingPutChangesNothing() {
        enabled = [1, 2]
        var ledger = HotKeyLedger()
        apply(ledger.move(to: [1], isEnabled: enabled.contains))
        XCTAssertEqual(ledger.move(to: [1], isEnabled: enabled.contains), HotKeyChanges(disable: [], enable: []))
    }

    func testALedgerReadBackAfterACrashRestoresEverything() {
        // The last run switched 1 and 64 off and never got to put them back.
        enabled = [2]
        var ledger = HotKeyLedger(disabledByUs: [1, 64])
        XCTAssertEqual(ledger.restoreAll(), HotKeyChanges(disable: [], enable: [1, 64]))
        XCTAssertEqual(ledger.disabledByUs, [])
    }
}
