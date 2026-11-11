import XCTest
@testable import MacsBoredCore

/// The settings file as people and agents write it.
final class ConfigFileTests: XCTestCase {
    private let sample = """
    {
      "$schema": "./config.schema.json",
      "enabled": true,
      "openAtLogin": true,
      "pauseKeys": "ctrl+opt+cmd+P",
      "capsLockAsHyper": false,
      "passthrough": [
        {
          "name": "Windows App",
          "apps": ["com.microsoft.rdc.macos"],
          "shortcuts": ["appSwitcher", "spotlight"],
          "sendEveryKey": false,
          "modifiers": "swapCommandControl"
        }
      ],
      "triggers": [
        { "name": "Focus timer", "keys": "ctrl+opt+F", "action": { "runShortcut": "Start a Focus timer" } },
        { "name": "Spotlight", "keys": "cmd+space", "action": { "passThrough": true }, "apps": ["com.microsoft.rdc.macos"] },
        {
          "name": "Open Notes",
          "keys": "ctrl+opt+N",
          "enabled": false,
          "action": { "openApp": "com.apple.Notes" },
          "when": [
            { "unless": "onBattery" },
            { "if": "timeBetween", "from": "09:00", "to": "17:30" }
          ]
        },
        { "name": "Shot", "keys": "hyper+S", "action": { "sendKeys": "shift+cmd+4" } },
        { "name": "Plan", "keys": "F13", "action": { "open": "~/Documents/plan.pdf" }, "when": { "any": [{ "if": "fullScreen" }, { "if": "windowTitleContains", "text": "Prod" }] } }
      ]
    }
    """

    private func read(_ text: String) -> ConfigFile.Reading { ConfigFile.read(Data(text.utf8)) }

    private func errors(_ text: String) -> [ConfigFile.Issue] { read(text).issues.filter { !$0.isWarning } }

    func testTheSampleReadsAsWritten() throws {
        let reading = read(sample)
        XCTAssertEqual(reading.issues, [])
        let config = try XCTUnwrap(reading.config)
        XCTAssertTrue(config.passthroughEnabled)
        XCTAssertEqual(config.openAtLogin, true)
        XCTAssertEqual(config.pauseKeys, KeyCombo(text: "ctrl+opt+cmd+P"))
        XCTAssertFalse(config.hyperKeyEnabled)

        let profile = try XCTUnwrap(config.profiles.first)
        XCTAssertEqual(profile.name, "Windows App")
        XCTAssertTrue(profile.isEnabled)
        XCTAssertEqual(profile.apps.map(\.bundleID), ["com.microsoft.rdc.macos"])
        XCTAssertEqual(profile.apps.first?.name, "Windows App", "a known app gets its name")
        XCTAssertEqual(profile.systemShortcuts, [.appSwitcher, .spotlight])
        XCTAssertEqual(profile.modifierLayout, .swapCommandControl)

        let t = config.triggers
        XCTAssertEqual(t.map(\.name), ["Focus timer", "Spotlight", "Open Notes", "Shot", "Plan"])
        XCTAssertEqual(t[0].action, .runShortcut("Start a Focus timer"))
        XCTAssertEqual(t[0].keys, [KeyCombo(text: "ctrl+opt+F")!])
        XCTAssertEqual(t[1].action, .passThrough)
        XCTAssertEqual(t[1].apps.map(\.bundleID), ["com.microsoft.rdc.macos"])
        XCTAssertEqual(t[2].action, .openApp(AppRef(bundleID: "com.apple.Notes", name: "com.apple.Notes")))
        XCTAssertFalse(t[2].isEnabled)
        XCTAssertEqual(t[2].conditions.match, .all)
        XCTAssertEqual(t[2].conditions.conditions.map(\.kind), [.onBattery, .timeBetween(start: 540, end: 1050)])
        XCTAssertEqual(t[2].conditions.conditions.map(\.negated), [true, false])
        XCTAssertEqual(t[3].action, .sendKeys(KeyCombo(text: "shift+cmd+4")!))
        XCTAssertEqual(t[4].action, .open("~/Documents/plan.pdf"))
        XCTAssertEqual(t[4].conditions.match, .any)
        XCTAssertEqual(t[4].conditions.conditions.map(\.kind), [.fullScreen, .windowTitleContains("Prod")])
    }

    func testAnEmptyObjectIsTheDefaults() throws {
        let config = try XCTUnwrap(read("{}").config)
        XCTAssertTrue(config.passthroughEnabled)
        XCTAssertNil(config.openAtLogin)
        XCTAssertEqual(config.pauseKeys, MacsBoredConfig.defaultPauseKeys)
        XCTAssertEqual(config.profiles, [])
        XCTAssertEqual(config.triggers, [])

        let profile = try XCTUnwrap(read(#"{"passthrough": [{"apps": ["com.citrix.receiver.icaviewer.mac"]}]}"#).config?.profiles.first)
        XCTAssertEqual(profile.name, "Citrix Viewer", "named after its app")
        XCTAssertEqual(profile.systemShortcuts, SystemShortcutGroup.defaultSet)
        XCTAssertEqual(profile.modifierLayout, .asIs)
        XCTAssertFalse(profile.captureAllKeys)
    }

    func testNullPauseKeysMeansNone() throws {
        XCTAssertNil(try XCTUnwrap(read(#"{"pauseKeys": null}"#).config).pauseKeys)
    }

    func testAMistakeIsAnErrorOnItsLineAndNoConfig() {
        let text = sample.replacingOccurrences(of: #""openApp": "com.apple.Notes""#, with: #""openApps": "com.apple.Notes""#)
        let reading = read(text)
        XCTAssertNil(reading.config)
        XCTAssertEqual(reading.issues.count, 1)
        XCTAssertEqual(reading.issues.first?.line, 23)
        XCTAssertEqual(reading.issues.first?.message,
                       "“openApps” isn't an action. Use sendKeys, openApp, runShortcut, passThrough or open.")
    }

    func testEachKindOfMistakeIsCaught() {
        XCTAssertEqual(errors("{").first?.line, 1)
        XCTAssertEqual(errors(#"{"enabled": "yes"}"#).first?.message, "“enabled” should be true or false.")
        XCTAssertEqual(errors(#"{"pauseKeys": "ctrl+banana"}"#).first?.message,
                       "“ctrl+banana” isn't keys MacsBored knows. Write them like ctrl+opt+cmd+P or hyper+N.")
        XCTAssertEqual(errors(#"{"triggers": [{"keys": "cmd+P", "action": {}}]}"#).first?.message,
                       "A trigger needs an action, like { \"openApp\": \"com.apple.Notes\" }.")
        XCTAssertEqual(errors(#"{"triggers": [{"keys": "P", "action": {"passThrough": true}}]}"#).first?.message,
                       "“P” needs ⌘, ⌃ or ⌥ (or an F-key), or it would take over typing.")
        XCTAssertEqual(errors(#"{"passthrough": [{"apps": ["a.b"], "shortcuts": ["teleport"]}]}"#).first?.message,
                       "“teleport” isn't a shortcut group. Use " + SystemShortcutGroup.allCases.map(\.rawValue).joined(separator: ", ") + ".")
        XCTAssertEqual(errors(#"{"passthrough": [{"apps": []}]}"#).first?.message,
                       "A passthrough entry needs at least one app, by bundle ID.")
        XCTAssertEqual(errors(#"{"triggers": [{"keys": "cmd+1", "action": {"passThrough": true}, "when": [{"if": "sunny"}]}]}"#).first?.message,
                       "“sunny” isn't a condition. Use fullScreen, fillsScreen, windowTitleContains, externalDisplay, onBattery, timeBetween or capsLock.")
        XCTAssertEqual(errors(#"{"triggers": [{"keys": "cmd+1", "action": {"passThrough": true}, "when": [{"if": "timeBetween", "from": "9am", "to": "17:00"}]}]}"#).first?.message,
                       "“9am” isn't a time. Write it like \"09:00\".")
        XCTAssertEqual(errors(#"{"triggers": [{"keys": "cmd+1", "action": {"open": "x", "openApp": "y"}}]}"#).first?.message,
                       "An action has one kind, but this one has 2: open, openApp.")
    }

    func testATriggerCanHaveSeveralKeys() throws {
        let text = #"{"triggers": [{"name": "Session keys", "keys": ["cmd+space", "cmd+tab"], "action": {"passThrough": true}}]}"#
        let config = try XCTUnwrap(read(text).config)
        XCTAssertEqual(config.triggers.first?.keys, [KeyCombo(text: "cmd+space")!, KeyCombo(text: "cmd+tab")!])
        XCTAssertTrue(ConfigFile.written(config).contains(#""keys": ["cmd+space", "cmd+tab"]"#), ConfigFile.written(config))
    }

    func testATriggerWithNoKeysIsWrittenAsNull() throws {
        let config = try XCTUnwrap(read(#"{"triggers": [{"name": "Later", "keys": [], "action": {"passThrough": true}}]}"#).config)
        XCTAssertEqual(config.triggers.first?.keys, [])
        XCTAssertTrue(ConfigFile.written(config).contains(#""keys": null"#))
    }

    func testAMistakeInAListOfKeysIsNamed() {
        XCTAssertEqual(errors(#"{"triggers": [{"keys": ["cmd+space", "cmd+banana"], "action": {"passThrough": true}}]}"#).first?.message,
                       "“cmd+banana” isn't keys MacsBored knows. Write them like ctrl+opt+cmd+P or hyper+N.")
    }

    func testUnknownFieldsAreWarnedAboutAndKept() throws {
        let text = #"""
        {
          "theme": "dark",
          "triggers": [
            { "name": "A", "keys": "cmd+1", "action": { "passThrough": true }, "note": "mine" }
          ]
        }
        """#
        let reading = read(text)
        XCTAssertEqual(reading.issues, [
            ConfigFile.Issue(line: 2, message: "“theme” isn't a MacsBored setting; it's kept as it is.", isWarning: true),
            ConfigFile.Issue(line: 4, message: "“note” isn't a trigger field; it's kept as it is.", isWarning: true),
        ])
        let written = ConfigFile.written(try XCTUnwrap(reading.config))
        XCTAssertTrue(written.contains(#""theme": "dark""#), written)
        XCTAssertTrue(written.contains(#""note": "mine""#), written)
    }

    func testWhatIsWrittenReadsBackTheSame() throws {
        let config = try XCTUnwrap(read(sample).config)
        let again = try XCTUnwrap(read(ConfigFile.written(config)).config)
        XCTAssertEqual(ConfigFile.written(again), ConfigFile.written(config))
        XCTAssertEqual(again.triggers.map(\.action), config.triggers.map(\.action))
        XCTAssertEqual(read(ConfigFile.written(config)).issues, [])
    }

    func testWrittenTheWayPeopleWriteIt() throws {
        var config = MacsBoredConfig()
        config.openAtLogin = true
        config.profiles = [PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")],
                                              systemShortcuts: [.spotlight, .appSwitcher])]
        config.triggers = [Trigger(name: "Focus timer", keys: [KeyCombo(text: "ctrl+opt+F")!], action: .runShortcut("Start a Focus timer"))]
        XCTAssertEqual(ConfigFile.written(config), """
        {
          "$schema": "./config.schema.json",
          "enabled": true,
          "openAtLogin": true,
          "pauseKeys": "ctrl+opt+cmd+P",
          "capsLockAsHyper": false,
          "passthrough": [
            {
              "name": "Windows App",
              "apps": ["com.microsoft.rdc.macos"],
              "shortcuts": ["appSwitcher", "spotlight"],
              "sendEveryKey": false,
              "modifiers": "asIs"
            }
          ],
          "triggers": [
            {
              "name": "Focus timer",
              "keys": "ctrl+opt+F",
              "action": { "runShortcut": "Start a Focus timer" }
            }
          ],
          "setupCompleted": false
        }

        """)
    }

    func testTheOldFormatIsConverted() throws {
        let old = """
        {
          "hyperKeyEnabled": true, "keepAwake": false, "passthroughEnabled": true, "setupCompleted": true,
          "pauseKeys": { "keyCode": 35, "modifiers": 11 },
          "profiles": [{
            "apps": [{ "bundleID": "com.microsoft.rdc.macos", "name": "Windows App" }],
            "captureAllKeys": true,
            "conditions": { "conditions": [{ "id": "6A6535B9-C2E9-4034-9261-2B7AFA6DCAEB", "kind": { "timeBetween": { "start": 60, "end": 120 } }, "negated": true }], "match": "any" },
            "id": "6A6535B9-C2E9-4034-9261-2B7AFA6DCAEB", "isEnabled": false, "modifierLayout": "swapCommandControl",
            "name": "Work PC", "systemShortcuts": ["appSwitcher", "spotlight"]
          }],
          "triggers": [
            { "id": "F9A1E581-E9B8-4444-954C-DFB952FB7DD1", "name": "Home", "isEnabled": true,
              "shortcut": { "keyCode": 123, "modifiers": 8 }, "action": { "sendShortcut": { "_0": { "keyCode": 115, "modifiers": 0 } } },
              "apps": [{ "bundleID": "com.apple.Safari", "name": "Safari" }], "conditions": { "conditions": [], "match": "all" } },
            { "id": "A9A1E581-E9B8-4444-954C-DFB952FB7DD1", "name": "Snippet", "isEnabled": true,
              "shortcut": { "keyCode": 17, "modifiers": 15 }, "action": { "typeText": { "_0": "Hi" } }, "apps": [], "conditions": {} }
          ]
        }
        """
        let reading = read(old)
        let config = try XCTUnwrap(reading.config)
        XCTAssertTrue(config.hyperKeyEnabled)
        XCTAssertTrue(config.setupCompleted)
        XCTAssertEqual(config.pauseKeys, MacsBoredConfig.defaultPauseKeys)
        let profile = try XCTUnwrap(config.profiles.first)
        XCTAssertEqual(profile.name, "Work PC")
        XCTAssertFalse(profile.isEnabled)
        XCTAssertTrue(profile.captureAllKeys)
        XCTAssertEqual(profile.modifierLayout, .swapCommandControl)
        XCTAssertEqual(profile.systemShortcuts, [.appSwitcher, .spotlight])
        XCTAssertEqual(profile.conditions, ConditionSet(match: .any, conditions: [Condition(.timeBetween(start: 60, end: 120), negated: true, id: profile.conditions.conditions[0].id)]))
        XCTAssertEqual(config.triggers.map(\.name), ["Home"])
        XCTAssertEqual(config.triggers.first?.action, .sendKeys(KeyCombo(keyCode: 115, modifiers: [])))
        XCTAssertEqual(config.triggers.first?.keys, [KeyCombo(keyCode: 123, modifiers: .command)])
        XCTAssertEqual(config.triggers.first?.apps.map(\.name), ["Safari"])
        XCTAssertEqual(reading.issues, [ConfigFile.Issue(line: nil, message: "“Snippet” typed text, which MacsBored no longer does, so it was left out.", isWarning: true)])
    }
}
