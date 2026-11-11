import XCTest
@testable import MacsBoredCore

/// The editor's one draft: four tabs, each making a trigger or a passthrough app.
final class EntryDraftTests: XCTestCase {
    private let windows = AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")
    private let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")
    private let keys = KeyCombo(text: "ctrl+opt+N")!

    func testANewDraftStartsOnRemapAndSaysWhatsMissing() {
        var draft = EntryDraft()
        XCTAssertEqual(draft.tab, .remap)
        XCTAssertEqual(draft.name, "Remap keys")
        XCTAssertEqual(draft.missing, "Record the keys to save")
        draft.keys = [keys]
        XCTAssertEqual(draft.missing, "Choose the keys to press")
        draft.sendKeys = KeyCombo(text: "cmd+left")
        XCTAssertNil(draft.missing)
        XCTAssertEqual(draft.name, "Press ⌘←")
        guard case let .trigger(trigger)? = draft.result else { return XCTFail("a trigger") }
        XCTAssertEqual(trigger.action, .sendKeys(KeyCombo(text: "cmd+left")!))
        XCTAssertEqual(trigger.keys, [keys])
        XCTAssertEqual(trigger.name, "Press ⌘←")
    }

    func testEachTabMakesItsAction() {
        var draft = EntryDraft()
        draft.keys = [keys]
        draft.tab = .open
        XCTAssertEqual(draft.missing, "Choose an app")
        draft.app = notes
        XCTAssertEqual(draft.name, "Open Notes")
        XCTAssertEqual(draft.trigger?.action, .openApp(notes))
        draft.openTarget = .link
        XCTAssertEqual(draft.missing, "Enter a link")
        draft.link = "https://github.com/expiracy"
        XCTAssertEqual(draft.name, "Open github.com")
        XCTAssertEqual(draft.trigger?.action, .open("https://github.com/expiracy"))
        draft.openTarget = .file
        draft.file = "~/Documents/Plan.pdf"
        XCTAssertEqual(draft.name, "Open Plan.pdf")
        XCTAssertEqual(draft.trigger?.action, .open("~/Documents/Plan.pdf"))
        draft.tab = .shortcut
        XCTAssertEqual(draft.missing, "Choose a Shortcut")
        draft.shortcutName = "Start a Focus timer"
        XCTAssertEqual(draft.trigger?.action, .runShortcut("Start a Focus timer"))
        draft.tab = .passthrough
        draft.passMode = .someKeys
        XCTAssertEqual(draft.name, "Pass ⌃⌥N to the app")
        XCTAssertEqual(draft.trigger?.action, .passThrough)
    }

    func testPassingSomeKeysTakesSeveral() {
        var draft = EntryDraft()
        draft.tab = .passthrough
        draft.passMode = .someKeys
        XCTAssertEqual(draft.missing, "Record the keys to save")
        draft.keys = [KeyCombo(text: "cmd+space")!]
        XCTAssertEqual(draft.name, "Pass ⌘Space to the app")
        draft.keys.append(KeyCombo(text: "cmd+tab")!)
        XCTAssertEqual(draft.name, "Pass ⌘Space and ⌘⇥ to the app")
        draft.keys.append(KeyCombo(text: "ctrl+left")!)
        XCTAssertEqual(draft.name, "Pass 3 shortcuts to the app")
        XCTAssertEqual(draft.trigger?.keys.count, 3)
        XCTAssertTrue(draft.preview.contains(#""keys": ["cmd+space", "cmd+tab", "ctrl+left"]"#), draft.preview)
    }

    func testAWholeAppIsAPassthroughEntry() {
        var draft = EntryDraft()
        draft.tab = .passthrough
        XCTAssertEqual(draft.missing, "Add an app to save")
        XCTAssertEqual(draft.name, "Passthrough app")
        draft.apps = [windows]
        draft.captureAllKeys = true
        guard case let .profile(profile)? = draft.result else { return XCTFail("a passthrough app") }
        XCTAssertEqual(profile.name, "Windows App")
        XCTAssertEqual(profile.apps, [windows])
        XCTAssertTrue(profile.captureAllKeys)
        XCTAssertEqual(profile.systemShortcuts, SystemShortcutGroup.defaultSet)
    }

    func testAYourOwnNameStaysAcrossTabs() {
        var draft = EntryDraft()
        draft.customName = "Mine"
        draft.tab = .shortcut
        XCTAssertEqual(draft.name, "Mine")
        draft.customName = ""
        XCTAssertEqual(draft.name, "Run a Shortcut")
    }

    func testAppsOnlyLimitATriggerWhenAskedTo() {
        var draft = EntryDraft()
        draft.keys = [keys]
        draft.tab = .passthrough
        draft.passMode = .someKeys
        draft.apps = [windows]
        XCTAssertEqual(draft.trigger?.apps, [])
        draft.onlyInApps = true
        XCTAssertEqual(draft.trigger?.apps, [windows])
    }

    func testEditingATriggerOpensOnItsTabAndKeepsItsID() {
        let trigger = Trigger(name: "Docs", isEnabled: false, keys: [keys], action: .open("~/Docs"), apps: [notes])
        let draft = EntryDraft(trigger: trigger)
        XCTAssertEqual(draft.origin, .trigger(trigger.id))
        XCTAssertEqual(draft.tab, .open)
        XCTAssertEqual(draft.openTarget, .file)
        XCTAssertEqual(draft.name, "Docs")
        XCTAssertTrue(draft.onlyInApps)
        XCTAssertEqual(draft.trigger?.id, trigger.id)
        XCTAssertEqual(draft.trigger, trigger)

        let link = EntryDraft(trigger: Trigger(name: "Open example.com", keys: [keys], action: .open("https://example.com")))
        XCTAssertEqual(link.openTarget, .link)
        XCTAssertEqual(link.customName, "", "a name that was only the suggestion keeps following it")
    }

    func testEditingAPassthroughAppOpensOnTheWholeApp() {
        let profile = PassthroughProfile(name: "Work PC", apps: [windows], systemShortcuts: [.spotlight], modifierLayout: .swapCommandControl)
        let draft = EntryDraft(profile: profile)
        XCTAssertEqual(draft.tab, .passthrough)
        XCTAssertEqual(draft.passMode, .wholeApp)
        XCTAssertEqual(draft.profile, profile)
    }

    func testSwitchingAPassthroughAppToATriggerKeepsItsAppsAndConditions() {
        var draft = EntryDraft(profile: PassthroughProfile(name: "Windows App", apps: [windows],
                                                           conditions: ConditionSet(conditions: [Condition(.fullScreen)])))
        draft.passMode = .someKeys
        draft.keys = [keys]
        draft.onlyInApps = true
        let trigger = draft.trigger
        XCTAssertEqual(trigger?.apps, [windows])
        XCTAssertEqual(trigger?.conditions.conditions.map(\.kind), [.fullScreen])
        XCTAssertEqual(trigger?.name, "Pass ⌃⌥N to the app")
    }

    func testThePreviewIsTheEntryAsTheFileWritesIt() {
        var draft = EntryDraft()
        draft.keys = [keys]
        draft.tab = .open
        draft.app = notes
        XCTAssertEqual(draft.preview, """
        {
          "name": "Open Notes",
          "keys": "ctrl+opt+N",
          "action": { "openApp": "com.apple.Notes" }
        }

        """)
        draft.app = nil
        XCTAssertTrue(draft.preview.contains(#""action": { "openApp": null }"#), draft.preview)
    }
}
