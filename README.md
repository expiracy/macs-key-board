# MacsBored

Your Mac's shortcuts, sent to the computer you're remoting into.

MacsBored is a menu-bar app for macOS, a sibling of [MacsPane](https://github.com/expiracy/macs-pane).
When Windows App, Citrix Viewer or a virtual machine is in front, macOS stops taking ⌘⇥, ⌘Space, ⌃←/→,
the screenshot keys and the rest, so they reach the session as they would on a PC. Switch to any other
app and macOS has them back. Alongside that it runs your own shortcuts, BetterTouchTool style.

## Installing a test build

Requires macOS 14 or later, on Apple silicon or Intel.

1. Open the `MacsBored-<version>.dmg` made by `scripts/release.sh` and drag MacsBored into
   Applications.
2. Open MacsBored from Applications. It has no Dock icon: it lives in the menu bar, and setup opens
   the first time.
3. In setup, click **Grant Access** and switch MacsBored on in System Settings › Privacy & Security ›
   Accessibility. It needs this to see keys before macOS acts on them and to read whether a window is
   full screen.

Test builds are not signed by Apple, so macOS blocks the first open: click **Done**, then open System
Settings › Privacy & Security and click **Open Anyway** under the message about MacsBored. You do
this once. Later test builds keep the Accessibility permission. The disk image has these steps in
*How to open MacsBored.txt*.

To remove MacsBored, quit it from its menu (which gives macOS back all its shortcuts), then delete it
from Applications and `~/Library/Application Support/MacsBored`.

## Using it

- **Passthrough apps.** Each names the apps it covers, when it acts, and which of macOS's shortcuts go
  to the app instead: the app switcher, Spotlight, Mission Control, Spaces, screenshots, input sources,
  the Dock and Notification Centre, keyboard navigation, Zoom and Help search. The menu's *Now* box
  offers to add the app in front; setup offers any remote-desktop app installed on first run.
- **Conditions.** A passthrough or trigger can wait for any of these: the window is full screen, the
  window fills the screen, the window title contains some text, an external display is connected, the
  Mac is on battery, the time is between two times, or Caps Lock is on. Each can be turned round
  (*Unless*), and they combine as *All* or *Any*.
- **Pause.** ⌃⌥⌘P inside a passthrough app gives macOS its shortcuts back so you can ⌘⇥ out. It resumes
  by itself once another app is in front.
- **Keys.** *Send every key straight to the app* also keeps other apps' global shortcuts (Raycast,
  Alfred, window managers) out of the session; it is off until you switch it on. *Modifier keys* can
  swap ⌘ and ⌃, so ⌘C is Ctrl+C in Windows and ⌃ is the Windows key.
- **Triggers.** Keys that do one thing, anywhere or only in some apps, under the same conditions: press
  other keys instead (a remap), open an app, a link or a file, run one of Apple's Shortcuts, or pass just
  those keys straight to the app in front. A trigger with no apps works everywhere except inside a
  passthrough app, whose keys belong to the session; name the passthrough app to have it work there too.
  Giving a trigger keys another trigger had takes them from it.
- **Caps Lock is Hyper.** Caps Lock holds ⌃⌥⇧⌘, a combination no app uses, for your triggers. It is
  remapped with `hidutil` for this login session and put back when you switch it off or quit; if another
  tool already remaps keys, it stays off.

There is no separate Settings window: it is all in the menu. *New* opens the editor, whose tabs pick
what you're making (Remap Keys, Open, Run Shortcut, Passthrough), and the pencil on a row opens it on
that entry. The menu's Setup button opens setup again.

## The settings file

Everything lives in `~/Library/Application Support/MacsBored/config.json`, written to be edited by hand,
by scripts or by an AI agent. MacsBored watches it: a valid change applies as soon as it's saved. A file
with a mistake is left alone, the last good settings keep running, and the menu names the line.

```json
{
  "enabled": true,
  "pauseKeys": "ctrl+opt+cmd+P",
  "passthrough": [{ "name": "Windows App", "apps": ["com.microsoft.rdc.macos"] }],
  "triggers": [
    { "name": "Open Notes", "keys": "ctrl+opt+N", "action": { "openApp": "com.apple.Notes" } },
    { "name": "Focus", "keys": "hyper+F", "action": { "runShortcut": "Start a Focus timer" },
      "when": [{ "unless": "onBattery" }] }
  ]
}
```

Keys are text (`ctrl+opt+cmd+P`, `hyper+N`, `cmd+space`; the menu's `⌃⌥⌘P` works too), and a trigger
can have several as a list (`"keys": ["cmd+space", "cmd+tab"]`), any of which sets it off. Apps are bundle
IDs, times are `"09:00"`, and entries need no IDs. An action is one of `sendKeys`, `openApp`,
`runShortcut`, `passThrough` (`true`) or `open`. `config.schema.json` beside the file describes every
field. Fields MacsBored doesn't know are kept as they are. The first version's file
(`~/Library/Application Support/MacsKeyBored/config.json`) is converted once.

From a terminal, the app's executable answers three commands without starting the app:

```bash
/Applications/MacsBored.app/Contents/MacOS/MacsBored check
```

`check [file]` prints each problem with its line and exits 1 on an error; `path` prints where the file
is; `schema` prints the schema.

## How passthrough works

macOS's own shortcuts are "symbolic hot keys" that the WindowServer handles before any app sees the
keys. While a passthrough app is in front, MacsBored switches the chosen ones off with the private
SkyLight call AltTab also uses (`CGSSetSymbolicHotKeyEnabled`), and switches them back on when it isn't.

It only ever switches back on what it switched off, and never touches a shortcut that is off in System
Settings. On macOS 26 the WindowServer reports every hot key as off, so MacsBored reads System
Settings' record (`com.apple.symbolichotkeys`) instead. The list of what it switched off is written to
disk before each change, so a crash or a force quit is undone on the next launch, and quitting (⌘Q,
`kill`, Ctrl-C) puts everything back.

An app's own menu shortcuts, such as ⌘Q or ⌘H in Windows App itself, belong to that app rather than to
macOS, so they stay with it.

## Building

Requires macOS 14 or later. The package builds with the Command Line Tools; the tests and the signed
`.app` use Xcode, and the Xcode project comes from [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
swift build              # build everything
swift test               # run the Core tests
scripts/run.sh           # build a MacsBored.app bundle and open it
scripts/make_icon.sh     # redraw App/AppIcon.icns and App/AppIcon.icon from the code
```

`swift run macsbored` also works, but Accessibility is granted per signed app. `scripts/run.sh`
signs with a requirement on the bundle identifier alone, so one grant lasts across rebuilds (or set
`MACSBORED_SIGN_IDENTITY=…` to use your own identity).

For the Xcode project: `xcodegen generate`, then build the `MacsBored` scheme.

### Releasing

`scripts/release.sh beta.1` runs the tests, builds for Apple silicon and Intel, signs the app and packs
it in `dist/MacsBored-<version>-beta.1.dmg` with its SHA-256. The version is in `VERSION`; the build
number is the commit count, so every release is newer than the last.

To give it to other people, sign it with a Developer ID (from the Apple Developer Program) and have
Apple notarize it:

```sh
xcrun notarytool store-credentials macsbored --apple-id <email> --team-id <TEAMID>   # once
MACSBORED_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
MACSBORED_NOTARY_PROFILE=macsbored scripts/release.sh
```

Every release signed with the same Developer ID keeps the Accessibility permission people already
gave. Without an identity the script makes an ad-hoc test build, with *How to open MacsBored.txt* in
the disk image. Its signature asks only for MacsBored's bundle identifier, so testers keep
Accessibility across test builds; any other ad-hoc app claiming that identifier would get it too, so use
a Developer ID before a wide release.

## How it's put together

| Target | What it holds |
|---|---|
| `MacsBoredCore` | Pure logic with no AppKit: profiles, conditions, triggers, the passthrough plan, the key router, the hot-key ledger, the settings file and its schema, and the editor's draft. Unit-tested. |
| `MacsBoredKit` | The app: the keyboard event tap (on its own thread), the system-shortcut switch, the Accessibility reads, the menu-bar dropdown, the editors and setup. |
| `macsbored` | The executable that boots `MacsBoredKit`. |

`macsbored --open-menu`, `--open-editor remap|open|shortcut|passthrough` and `--open-setup` open those
surfaces straight away, for looking at them without clicking through.

## License

Copyright (C) 2026 James Gray

MacsBored is free software: you can redistribute it and/or modify it under the terms of the GNU Affero
General Public License as published by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version. Anything built from it, including a modified version you only offer
to others over a network, must be released under the same license with its source. See
[LICENSE](LICENSE) for the full text.
