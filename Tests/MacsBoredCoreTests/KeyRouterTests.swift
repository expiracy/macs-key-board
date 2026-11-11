import XCTest
@testable import MacsBoredCore

final class KeyRouterTests: XCTestCase {
    private let windowsApp = AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")
    private let pauseKeys = KeyCombo(keyCode: KeyCombo.Code.p, modifiers: [.control, .option, .command])
    private let cmdTab = KeyCombo(keyCode: KeyCombo.Code.tab, modifiers: .command)

    private func plan(capture: Bool = true, layout: ModifierLayout = .asIs, pid: Int32 = 99) -> PassthroughPlan {
        PassthroughPlan(profileID: UUID(), profileName: "Windows", processID: pid, disabledHotKeys: [1],
                        captureAllKeys: capture, modifierLayout: layout)
    }

    private func setup(_ plan: PassthroughPlan = .inactive, triggers: [Trigger] = [], bundleID: String? = nil,
                       hyper: Bool = false) -> KeyRouter.Setup {
        KeyRouter.Setup(plan: plan, triggers: triggers, context: AppContext(bundleID: bundleID),
                        pauseKeys: pauseKeys, hyperKeyEnabled: hyper)
    }

    private func down(_ combo: KeyCombo, repeat isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(phase: .down, keyCode: combo.keyCode, modifiers: combo.modifiers, isRepeat: isRepeat)
    }

    private func up(_ combo: KeyCombo) -> KeyEvent {
        KeyEvent(phase: .up, keyCode: combo.keyCode, modifiers: combo.modifiers)
    }

    // MARK: - Passthrough

    func testWithNothingActiveKeysPassUntouched() {
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(cmdTab), setup()), .pass)
    }

    func testCapturedKeysGoStraightToThePassthroughApp() {
        var router = KeyRouter()
        let s = setup(plan(pid: 7), bundleID: windowsApp.bundleID)
        XCTAssertEqual(router.route(down(cmdTab), s), .forward(pid: 7, keyCode: KeyCombo.Code.tab, modifiers: .command))
        XCTAssertEqual(router.route(up(cmdTab), s), .forward(pid: 7, keyCode: KeyCombo.Code.tab, modifiers: .command))
    }

    func testAKeyUpFollowsItsKeyDownAfterTheAppChanges() {
        var router = KeyRouter()
        _ = router.route(down(cmdTab), setup(plan(pid: 7), bundleID: windowsApp.bundleID))
        // The Windows session lost the front (a click elsewhere) before the key came up.
        XCTAssertEqual(router.route(up(cmdTab), setup()),
                       .forward(pid: 7, keyCode: KeyCombo.Code.tab, modifiers: .command))
        XCTAssertEqual(router.route(up(cmdTab), setup()), .pass)
    }

    func testSwapLayoutTurnsCommandIntoControlWithoutCapture() {
        var router = KeyRouter()
        let s = setup(plan(capture: false, layout: .swapCommandControl), bundleID: windowsApp.bundleID)
        let cmdC = KeyCombo(keyCode: 8, modifiers: [.command, .shift])
        XCTAssertEqual(router.route(down(cmdC), s), .modify(keyCode: 8, modifiers: [.control, .shift]))
        // The ⌘ key itself going down reads as the ⌃ key.
        let commandKey = KeyEvent(phase: .flagsChanged, keyCode: KeyCombo.Code.leftCommand, modifiers: .command)
        XCTAssertEqual(router.route(commandKey, s), .modify(keyCode: KeyCombo.Code.leftControl, modifiers: .control))
        let controlUp = KeyEvent(phase: .flagsChanged, keyCode: KeyCombo.Code.rightControl, modifiers: [])
        XCTAssertEqual(router.route(controlUp, s), .modify(keyCode: KeyCombo.Code.rightCommand, modifiers: []))
    }

    func testSwapLayoutAppliesToCapturedKeysToo() {
        var router = KeyRouter()
        let s = setup(plan(capture: true, layout: .swapCommandControl, pid: 3), bundleID: windowsApp.bundleID)
        XCTAssertEqual(router.route(down(cmdTab), s), .forward(pid: 3, keyCode: KeyCombo.Code.tab, modifiers: .control))
    }

    func testModifierKeysAloneAreNotCaptured() {
        var router = KeyRouter()
        let s = setup(plan(), bundleID: windowsApp.bundleID)
        let shiftKey = KeyEvent(phase: .flagsChanged, keyCode: 56, modifiers: .shift)
        XCTAssertEqual(router.route(shiftKey, s), .pass)
    }

    // MARK: - Pause

    func testThePauseKeysAreTakenEvenInsideAPassthroughApp() {
        var router = KeyRouter()
        let s = setup(plan(), bundleID: windowsApp.bundleID)
        XCTAssertEqual(router.route(down(pauseKeys), s), .togglePause)
        XCTAssertEqual(router.route(up(pauseKeys), s), .swallow)
        XCTAssertEqual(router.route(down(pauseKeys, repeat: true), s), .swallow)
    }

    // MARK: - Triggers

    func testAnEverywhereTriggerRunsOutsidePassthroughOnly() {
        let trigger = Trigger(name: "Terminal", keys: [KeyCombo(keyCode: 17, modifiers: [.control, .option])],
                              action: .openApp(AppRef(bundleID: "com.apple.Terminal", name: "Terminal")))
        var router = KeyRouter()
        let keys = trigger.keys[0]
        XCTAssertEqual(router.route(down(keys), setup(triggers: [trigger], bundleID: "com.apple.Safari")),
                       .runTrigger(trigger.id))
        XCTAssertEqual(router.route(up(keys), setup(triggers: [trigger], bundleID: "com.apple.Safari")), .swallow)
        XCTAssertEqual(router.route(down(keys), setup(plan(capture: false), triggers: [trigger],
                                                       bundleID: windowsApp.bundleID)), .pass)
    }

    func testATriggerNamingThePassthroughAppRunsThere() {
        let trigger = Trigger(name: "Home", keys: [KeyCombo(keyCode: 123, modifiers: .command)],
                              action: .sendKeys(KeyCombo(keyCode: 115, modifiers: [])), apps: [windowsApp])
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(trigger.keys[0]), setup(plan(), triggers: [trigger],
                                                                   bundleID: windowsApp.bundleID)),
                       .runTrigger(trigger.id))
    }

    func testAHeldTriggerRunsOnce() {
        let trigger = Trigger(name: "Snippet", keys: [KeyCombo(keyCode: 17, modifiers: [.control, .option])],
                              action: .runShortcut("Hello"))
        var router = KeyRouter()
        let s = setup(triggers: [trigger])
        XCTAssertEqual(router.route(down(trigger.keys[0]), s), .runTrigger(trigger.id))
        XCTAssertEqual(router.route(down(trigger.keys[0], repeat: true), s), .swallow)
    }

    func testAPassThroughTriggerSendsItsOwnKeysToTheAppInFront() {
        let spotlight = KeyCombo(keyCode: KeyCombo.Code.space, modifiers: .command)
        let trigger = Trigger(name: "Spotlight in the session", keys: [spotlight], action: .passThrough)
        var router = KeyRouter()
        let s = KeyRouter.Setup(plan: .inactive, triggers: [trigger],
                                context: AppContext(bundleID: "com.microsoft.rdc.macos", processID: 42),
                                pauseKeys: pauseKeys, hyperKeyEnabled: false)
        XCTAssertEqual(router.route(down(spotlight), s), .forward(pid: 42, keyCode: KeyCombo.Code.space, modifiers: .command))
        XCTAssertEqual(router.route(down(spotlight, repeat: true), s), .forward(pid: 42, keyCode: KeyCombo.Code.space, modifiers: .command))
        XCTAssertEqual(router.route(up(spotlight), s), .forward(pid: 42, keyCode: KeyCombo.Code.space, modifiers: .command))
    }

    func testAPassThroughTriggerWithNoAppInFrontLetsTheKeysGo() {
        let trigger = Trigger(name: "P", keys: [cmdTab], action: .passThrough)
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(cmdTab), setup(triggers: [trigger])), .pass)
    }

    func testATriggerWithSeveralKeysFiresOnAnyOfThem() {
        let spotlight = KeyCombo(keyCode: KeyCombo.Code.space, modifiers: .command)
        let trigger = Trigger(name: "Session keys", keys: [spotlight, cmdTab], action: .passThrough)
        var router = KeyRouter()
        let s = KeyRouter.Setup(plan: .inactive, triggers: [trigger],
                                context: AppContext(bundleID: "com.microsoft.rdc.macos", processID: 42),
                                pauseKeys: pauseKeys, hyperKeyEnabled: false)
        XCTAssertEqual(router.route(down(cmdTab), s), .forward(pid: 42, keyCode: KeyCombo.Code.tab, modifiers: .command))
        XCTAssertEqual(router.route(down(spotlight), s), .forward(pid: 42, keyCode: KeyCombo.Code.space, modifiers: .command))
    }

    // MARK: - Hyper key

    func testCapsLockAsHyperHoldsAllFourModifiers() {
        var router = KeyRouter()
        let s = setup(hyper: true)
        let f18 = KeyCombo(keyCode: KeyCombo.Code.f18, modifiers: [])
        XCTAssertEqual(router.route(down(f18), s), .swallow)
        let t = KeyCombo(keyCode: 17, modifiers: [])
        XCTAssertEqual(router.route(down(t), s), .modify(keyCode: 17, modifiers: .hyper))
        XCTAssertEqual(router.route(up(f18), s), .swallow)
        XCTAssertEqual(router.route(down(t), s), .pass)
    }

    func testAHyperTriggerRuns() {
        let trigger = Trigger(name: "Hyper T", keys: [KeyCombo(keyCode: 17, modifiers: .hyper)],
                              action: .open("https://example.com"))
        var router = KeyRouter()
        let s = setup(triggers: [trigger], hyper: true)
        _ = router.route(down(KeyCombo(keyCode: KeyCombo.Code.f18, modifiers: [])), s)
        XCTAssertEqual(router.route(down(KeyCombo(keyCode: 17, modifiers: [])), s), .runTrigger(trigger.id))
    }

    func testF18IsAnOrdinaryKeyWithHyperOff() {
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(KeyCombo(keyCode: KeyCombo.Code.f18, modifiers: [])), setup()), .pass)
    }
}
