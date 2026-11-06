import XCTest
@testable import MacsKeyBoredCore

final class ConditionTests: XCTestCase {
    func testNoConditionsAlwaysHold() {
        XCTAssertTrue(ConditionSet().isSatisfied(by: AppContext()))
        XCTAssertTrue(ConditionSet(match: .any).isSatisfied(by: AppContext()))
    }

    func testNegatedConditionHoldsWhenTheThingIsFalse() {
        let notFullScreen = Condition(.fullScreen, negated: true)
        XCTAssertTrue(notFullScreen.isSatisfied(by: AppContext(isFullScreen: false)))
        XCTAssertFalse(notFullScreen.isSatisfied(by: AppContext(isFullScreen: true)))
    }

    func testFillsScreenCountsFullScreenToo() {
        let fills = Condition(.fillsScreen)
        XCTAssertTrue(fills.isSatisfied(by: AppContext(isFullScreen: true)))
        XCTAssertTrue(fills.isSatisfied(by: AppContext(fillsScreen: true)))
        XCTAssertFalse(fills.isSatisfied(by: AppContext()))
    }

    func testWindowTitleMatchesIgnoringCase() {
        let title = Condition(.windowTitleContains("desktop"))
        XCTAssertTrue(title.isSatisfied(by: AppContext(windowTitle: "Work Desktop - Windows 11")))
        XCTAssertFalse(title.isSatisfied(by: AppContext(windowTitle: "Connection Center")))
        XCTAssertFalse(title.isSatisfied(by: AppContext(windowTitle: nil)))
        // Nothing typed yet is no condition at all.
        XCTAssertTrue(Condition(.windowTitleContains("  ")).isSatisfied(by: AppContext(windowTitle: nil)))
    }

    func testTimeRangeWithinADayAndOverMidnight() {
        let workHours = Condition(.timeBetween(start: 9 * 60, end: 17 * 60))
        XCTAssertTrue(workHours.isSatisfied(by: AppContext(minuteOfDay: 9 * 60)))
        XCTAssertFalse(workHours.isSatisfied(by: AppContext(minuteOfDay: 17 * 60)))
        XCTAssertFalse(workHours.isSatisfied(by: AppContext(minuteOfDay: 8 * 60 + 59)))

        let night = Condition(.timeBetween(start: 22 * 60, end: 6 * 60))
        XCTAssertTrue(night.isSatisfied(by: AppContext(minuteOfDay: 23 * 60)))
        XCTAssertTrue(night.isSatisfied(by: AppContext(minuteOfDay: 5 * 60)))
        XCTAssertFalse(night.isSatisfied(by: AppContext(minuteOfDay: 12 * 60)))
    }

    func testAllNeedsEveryOneAnyNeedsOne() {
        let conditions = [Condition(.fullScreen), Condition(.externalDisplay)]
        let onlyFullScreen = AppContext(isFullScreen: true)
        XCTAssertFalse(ConditionSet(match: .all, conditions: conditions).isSatisfied(by: onlyFullScreen))
        XCTAssertTrue(ConditionSet(match: .any, conditions: conditions).isSatisfied(by: onlyFullScreen))
        XCTAssertFalse(ConditionSet(match: .any, conditions: conditions).isSatisfied(by: AppContext()))
    }

    func testOtherKinds() {
        XCTAssertTrue(Condition(.onBattery).isSatisfied(by: AppContext(onBattery: true)))
        XCTAssertTrue(Condition(.externalDisplay).isSatisfied(by: AppContext(hasExternalDisplay: true)))
        XCTAssertTrue(Condition(.capsLock).isSatisfied(by: AppContext(capsLockOn: true)))
        XCTAssertFalse(Condition(.capsLock).isSatisfied(by: AppContext(capsLockOn: false)))
    }
}
