import XCTest
@testable import MacsBoredCore

final class PassthroughPlannerTests: XCTestCase {
    private let windowsApp = AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")
    private let citrix = AppRef(bundleID: "com.citrix.receiver.icaviewer.mac", name: "Citrix Viewer")

    private func context(_ bundleID: String?, fullScreen: Bool = false, pid: Int32 = 42) -> AppContext {
        AppContext(bundleID: bundleID, processID: pid, isFullScreen: fullScreen)
    }

    func testAnAppNoProfileCoversPassesNothing() {
        let profile = PassthroughProfile(name: "Windows", apps: [windowsApp])
        let plan = PassthroughPlanner.plan(profiles: [profile], context: context("com.apple.Safari"))
        XCTAssertEqual(plan, .inactive)
    }

    func testTheProfileForTheFrontAppSwitchesItsShortcutsOff() {
        let profile = PassthroughProfile(name: "Windows", apps: [windowsApp],
                                         systemShortcuts: [.appSwitcher, .spotlight],
                                         captureAllKeys: true, modifierLayout: .swapCommandControl)
        let plan = PassthroughPlanner.plan(profiles: [profile], context: context(windowsApp.bundleID, pid: 7))
        XCTAssertEqual(plan.profileID, profile.id)
        XCTAssertEqual(plan.processID, 7)
        XCTAssertEqual(plan.disabledHotKeys, [1, 2, 6, 27, 64, 65])
        XCTAssertTrue(plan.captureAllKeys)
        XCTAssertEqual(plan.modifierLayout, .swapCommandControl)
    }

    func testAProfileWaitsForItsConditions() {
        let profile = PassthroughProfile(name: "Citrix", apps: [citrix],
                                         conditions: ConditionSet(conditions: [Condition(.fullScreen)]))
        XCTAssertFalse(PassthroughPlanner.plan(profiles: [profile], context: context(citrix.bundleID)).isActive)
        XCTAssertTrue(PassthroughPlanner.plan(profiles: [profile],
                                              context: context(citrix.bundleID, fullScreen: true)).isActive)
    }

    func testASwitchedOffProfileOrAPauseDoesNothing() {
        var profile = PassthroughProfile(name: "Windows", apps: [windowsApp])
        XCTAssertFalse(PassthroughPlanner.plan(profiles: [profile], context: context(windowsApp.bundleID),
                                               paused: true).isActive)
        profile.isEnabled = false
        XCTAssertFalse(PassthroughPlanner.plan(profiles: [profile], context: context(windowsApp.bundleID)).isActive)
    }

    func testTheFirstProfileWhoseConditionsHoldWins() {
        let fullScreen = PassthroughProfile(name: "Full screen", apps: [windowsApp],
                                            conditions: ConditionSet(conditions: [Condition(.fullScreen)]),
                                            systemShortcuts: [.spotlight])
        let windowed = PassthroughProfile(name: "Windowed", apps: [windowsApp], systemShortcuts: [.appSwitcher])
        let profiles = [fullScreen, windowed]
        XCTAssertEqual(PassthroughPlanner.plan(profiles: profiles, context: context(windowsApp.bundleID)).profileID,
                       windowed.id)
        XCTAssertEqual(PassthroughPlanner.plan(profiles: profiles,
                                               context: context(windowsApp.bundleID, fullScreen: true)).profileID,
                       fullScreen.id)
    }
}
