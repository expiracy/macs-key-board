#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// The one editor, for everything MacsBored does. Tabs across the top pick what it is: remap keys,
/// open something, run a Shortcut, or pass keys through (a whole app, or only some keys). Every tab
/// shares the name, the keys, the apps and the conditions, so moving between them loses nothing.
/// The bottom bar shows the entry as `config.json` will hold it.
struct EntryEditor: View {
    @State var draft: EntryDraft
    let isNew: Bool
    @ObservedObject var model: MacsBoredModel
    let onSave: (EntryDraft.Result) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var recordingKeys = false
    @State private var recordingSend = false
    @State private var keysProblem: String?
    @State private var typing = false
    @State private var typed = ""
    @State private var showsFile = false
    @State private var copied = false
    @State private var confirmingDelete = false
    @State private var shortcutNames: [String] = []
    /// The form's own height, so the window fits it and only scrolls past `maxFormHeight`.
    @State private var formHeight: CGFloat = 400

    static let width: CGFloat = 760
    private static let maxFormHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(intro).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                    identity
                    if [.remap, .open, .shortcut].contains(draft.tab) { whatItDoes }
                    if draft.isPassthroughApp { passthroughApp } else { whereGroup }
                    FormGroup(title: "When", caption: draft.isPassthroughApp ? pauseNote : "With no conditions it always works.") {
                        if draft.conditions.conditions.isEmpty {
                            FormRow(divider: false) {
                                Text(draft.isPassthroughApp ? "Whenever one of these apps is in front" : "Always")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ConditionRows(conditions: $draft.conditions)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .controlSize(.large)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: FormHeightKey.self, value: proxy.size.height)
                })
            }
            // Its ideal height is the form's (up to a limit), which the window takes; any height the window
            // has beyond that goes to the form, so the bottom bar always sits on the window's bottom edge.
            .frame(idealHeight: min(formHeight, Self.maxFormHeight), maxHeight: .infinity)
            .onPreferenceChange(FormHeightKey.self) { formHeight = $0 }
            if showsFile { filePanel }
            Divider()
            bottomBar
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            let names = await Task.detached { ActionRunner.shortcutNames() }.value
            shortcutNames = names
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        VStack(spacing: 0) {
            Text(isNew ? "New" : draft.isPassthroughApp ? "Edit Passthrough App" : "Edit Trigger")
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 30)
            HStack(spacing: 6) {
                ForEach(EntryDraft.Tab.allCases, id: \.self) { tab in
                    let selected = draft.tab == tab
                    Button { switchTo(tab) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol).font(.system(size: 21))
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                                .frame(height: 24)
                            Text(tab.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(minWidth: 108, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(selected ? 0.08 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .help(help(tab))
                }
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    private func switchTo(_ tab: EntryDraft.Tab) {
        recordingKeys = false
        recordingSend = false
        if tab == .passthrough, draft.tab != .passthrough, draft.apps.isEmpty == false, draft.passMode == .someKeys {
            draft.onlyInApps = true
        }
        draft.tab = tab
    }

    private func help(_ tab: EntryDraft.Tab) -> String {
        switch tab {
        case .remap: "Press other keys instead"
        case .open: "Open an app, a link, or a file or folder"
        case .shortcut: "Run one of Apple's Shortcuts"
        case .passthrough: "Give an app, or just some keys, to the app in front instead of macOS"
        }
    }

    private var intro: String {
        switch draft.tab {
        case .remap: "Press one shortcut and MacsBored presses another for you: ⌘← for Home, say, or a long shortcut on one key."
        case .open: "One shortcut opens an app, a web link, or a file or folder."
        case .shortcut: "One shortcut runs one of Apple's Shortcuts, so anything the Shortcuts app can do is a key away."
        case .passthrough:
            draft.passMode == .wholeApp
                ? "A whole app gets macOS's own shortcuts, like ⌘⇥ and Spotlight, while it's in front: a remote desktop or a virtual machine."
                : "Just these keys go straight to the app in front instead of macOS: a few shortcuts, without passing a whole app through."
        }
    }

    // MARK: - Name and keys

    private var identity: some View {
        FormGroup {
            if draft.tab == .passthrough {
                FormRow(label: "Pass through", divider: false) {
                    Picker("Pass through", selection: $draft.passMode) {
                        Text("A whole app").tag(EntryDraft.PassMode.wholeApp)
                        Text("Only some keys").tag(EntryDraft.PassMode.someKeys)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                }
            }
            FormRow(label: "Name", divider: draft.tab == .passthrough) {
                TextField(draft.suggestedName, text: $draft.customName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: FormMetric.field)
                Spacer()
                if draft.isPassthroughApp {
                    Text(draft.isEnabled ? "On" : "Off").foregroundStyle(.secondary)
                    Toggle("On", isOn: $draft.isEnabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }
            if !draft.isPassthroughApp {
                FormRow(label: draft.tab == .passthrough ? "Keys to pass" : "Keys", top: true) { keysControl }
            }
        }
    }

    /// The keys as removable chips, then a field to record more. Passing keys through usually wants
    /// several (⌘Space, ⌘⇥…), so there the field keeps listening until esc.
    private var keysControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if typing {
                    TextField("ctrl+opt+N, cmd+space", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: FormMetric.field)
                        .onSubmit(commitTyped)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(draft.keys, id: \.self) { keyChip($0) }
                        KeyRecorderField(keys: Binding(get: { nil }, set: { add($0) }),
                                         recording: $recordingKeys,
                                         placeholder: draft.keys.isEmpty ? "Click to record" : "Add keys…",
                                         width: draft.keys.isEmpty ? FormMetric.field : 150,
                                         keepsRecording: draft.tab == .passthrough,
                                         onRefused: { keysProblem = $0 },
                                         model: model)
                    }
                    .frame(maxWidth: FormMetric.field + 140, alignment: .leading)
                }
                Spacer(minLength: 0)
                Button(typing ? "Record instead" : "Type instead") {
                    keysProblem = nil
                    if typing {
                        commitTyped()
                        if keysProblem == nil { typing = false }
                    } else {
                        typed = draft.keys.map(\.text).joined(separator: ", ")
                        typing = true
                    }
                }
                .controlSize(.small)
            }
            keysHint
        }
    }

    /// One set of keys as keycaps, with a button that takes it out.
    private func keyChip(_ keys: KeyCombo) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
            Button { draft.keys.removeAll { $0 == keys } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(keys.displayName)")
            .accessibilityLabel("Remove \(keys.displayName)")
        }
        .padding(.leading, 4).padding(.trailing, 2)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func add(_ keys: KeyCombo?) {
        guard let keys else { return }
        keysProblem = nil
        if !draft.keys.contains(keys) { draft.keys.append(keys) }
    }

    /// Typed keys, as the settings file writes them; several are separated by commas.
    private func commitTyped() {
        var parsed: [KeyCombo] = []
        for part in typed.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            guard let keys = KeyCombo(text: part) else {
                keysProblem = "“\(part)” isn't keys MacsBored knows. Write them like ctrl+opt+cmd+P or hyper+N."
                return
            }
            guard keys.isUsableAsTrigger else {
                keysProblem = "“\(part)” on its own would take over typing. Add ctrl, opt or cmd, or use an F-key."
                return
            }
            if !parsed.contains(keys) { parsed.append(keys) }
        }
        keysProblem = nil
        draft.keys = parsed
        typed = parsed.map(\.text).joined(separator: ", ")
    }

    @ViewBuilder private var keysHint: some View {
        if let keysProblem {
            hint(keysProblem, symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else if recordingKeys {
            hint(draft.tab == .passthrough
                 ? "Press each shortcut the app should get, one after another. esc when you're done."
                 : "Hold the modifiers, then press a key. esc stops.")
        } else if typing {
            hint("As the settings file writes them, separated by commas: ctrl+opt+N, cmd+space. Return to use them.")
        } else {
            if let (keys, other) = clash {
                hint("\(keys.displayName) already runs “\(other.name)”. Saving moves it here.",
                     symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if !systemNotes.isEmpty {
                hint("macOS uses " + ListFormatter.localizedString(byJoining: systemNotes) + ". "
                     + (draft.tab == .passthrough ? "While this works, the app gets "
                        + (systemNotes.count == 1 ? "it" : "them") + " instead."
                        : "This trigger takes " + (systemNotes.count == 1 ? "it" : "them") + " over wherever it works."),
                     symbol: "info.circle")
            }
            let offered = picks.filter { !draft.keys.contains($0) }
            if !offered.isEmpty, draft.keys.isEmpty || draft.tab == .passthrough {
                HStack(spacing: 4) {
                    Text(draft.tab == .passthrough ? "Common:" : "Free to use:").font(.callout).foregroundStyle(.secondary)
                    ForEach(offered, id: \.self) { keys in
                        Button(keys.modifiers == .hyper ? "Hyper \(keys.keyName)" : keys.displayName) { add(keys) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// The first of these keys another trigger already has in the same place.
    private var clash: (KeyCombo, Trigger)? {
        for keys in draft.keys {
            if let other = model.trigger(using: keys, apps: draft.onlyInApps ? draft.apps : [], except: triggerID) {
                return (keys, other)
            }
        }
        return nil
    }

    /// "⌘Space to open Spotlight", for each of these keys macOS uses itself.
    private var systemNotes: [String] {
        draft.keys.compactMap { keys in Self.systemUses[keys].map { "\(keys.displayName) to \($0)" } }
    }

    private func hint(_ text: String, symbol: String? = nil, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            Text(text).foregroundStyle(tint == .orange ? Color.primary.opacity(0.75) : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private var triggerID: UUID? {
        if case let .trigger(id) = draft.origin { return id }
        return nil
    }

    /// A few keys to add with a click: ones nothing else here uses, or, to pass through, the shortcuts
    /// a session most often wants.
    private var picks: [KeyCombo] {
        let candidates = draft.tab == .passthrough
            ? ["cmd+space", "cmd+tab", "ctrl+left", "ctrl+right"]
            : ["ctrl+opt+N", "ctrl+opt+cmd+N", "hyper+N", "F13"]
        return candidates.compactMap(KeyCombo.init(text:)).filter { model.trigger(using: $0, apps: [], except: nil) == nil }
    }

    private static let systemUses: [KeyCombo: String] = {
        let uses = ["cmd+space": "open Spotlight", "cmd+tab": "switch apps", "shift+cmd+3": "take a screenshot",
                    "shift+cmd+4": "take a screenshot", "shift+cmd+5": "take a screenshot", "ctrl+up": "open Mission Control",
                    "ctrl+left": "move to the space on the left", "ctrl+right": "move to the space on the right",
                    "ctrl+space": "change the input source"]
        return Dictionary(uniqueKeysWithValues: uses.compactMap { text, use in KeyCombo(text: text).map { ($0, use) } })
    }()

    // MARK: - What it does

    private var whatItDoes: some View {
        FormGroup(title: "What it does", caption: whatCaption) {
            switch draft.tab {
            case .remap:
                FormRow(label: "Press instead", divider: false) {
                    KeyRecorderField(keys: $draft.sendKeys, recording: $recordingSend, allowPlain: true, model: model)
                    Spacer()
                }
            case .open:
                FormRow(label: "Open", divider: false) {
                    Picker("Open", selection: $draft.openTarget) {
                        Text("An app").tag(EntryDraft.OpenTarget.app)
                        Text("A link").tag(EntryDraft.OpenTarget.link)
                        Text("A file or folder").tag(EntryDraft.OpenTarget.file)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                }
                switch draft.openTarget {
                case .app:
                    FormRow(label: "App") { appPicker; Spacer() }
                case .link:
                    FormRow(label: "Link") {
                        TextField("https://…", text: $draft.link).textFieldStyle(.roundedBorder).frame(width: FormMetric.field)
                        Spacer()
                    }
                case .file:
                    FormRow(label: "File or folder") {
                        TextField("~/Documents/plan.pdf", text: $draft.file).textFieldStyle(.roundedBorder).frame(width: FormMetric.field)
                        Button("Choose…", action: chooseFile)
                        Spacer()
                    }
                }
            case .shortcut:
                FormRow(label: "Shortcut", divider: false) {
                    Picker("Shortcut", selection: $draft.shortcutName) {
                        Text("Choose a Shortcut").tag("")
                        ForEach(shortcutChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: FormMetric.field)
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    Spacer()
                }
            case .passthrough:
                EmptyView()
            }
        }
    }

    private var shortcutChoices: [String] {
        let names = shortcutNames
        return draft.shortcutName.isEmpty || names.contains(draft.shortcutName) ? names : [draft.shortcutName] + names
    }

    private var whatCaption: String {
        switch draft.tab {
        case .remap: return "The keys are pressed with exactly these modifiers, whatever you are holding."
        case .shortcut: return shortcutNames.isEmpty
            ? "Your Shortcuts from Apple's Shortcuts app appear here."
            : "From Apple's Shortcuts app: Home, Music, Reminders, or Shortcuts of your own."
        case .open:
            switch draft.openTarget {
            case .app: return "Opens the app, or brings it to the front if it is open."
            case .link: return "Opens in your default browser."
            case .file: return "Opens with its usual app; a folder opens in Finder."
            }
        case .passthrough: return ""
        }
    }

    private var appPicker: some View {
        HStack(spacing: 6) {
            if let app = draft.app, let icon = AppIcons.icon(bundleID: app.bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
            }
            appMenu.fixedSize()
        }
    }

    private var appMenu: some View {
        Menu {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .compactMap { app -> AppRef? in
                    guard let id = app.bundleIdentifier else { return nil }
                    return AppRef(bundleID: id, name: app.localizedName ?? id)
                }
            Section("Open now") { ForEach(running) { app in Button(app.name) { draft.app = app } } }
            Divider()
            Button("Choose an app…") { AppChooser.choose { draft.app = $0 } }
        } label: {
            Text(draft.app.map(AppIcons.name) ?? "Choose an app")
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.file = (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Where (triggers) and the passthrough app

    private var whereGroup: some View {
        FormGroup(title: "Where", caption: whereCaption) {
            FormRow(label: "Works", divider: false) {
                Picker("Works", selection: $draft.onlyInApps) {
                    Text("Everywhere").tag(false)
                    Text("Only in certain apps").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            if draft.onlyInApps {
                FormRow(label: "Apps", top: true) {
                    AppChips(apps: $draft.apps, suggestions: runningApps, suggestionsTitle: "Open now")
                }
            }
        }
    }

    private var whereCaption: String {
        if draft.onlyInApps { return "Works only while one of these apps is in front, a passthrough app included." }
        return draft.tab == .passthrough
            ? "Works in every app. Pick the apps if only some should get these keys."
            : "Works in every app except a passthrough app, whose keys belong to the remote session."
    }

    private var runningApps: [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { AppRef(bundleID: $0, name: app.localizedName ?? $0) } }
    }

    @ViewBuilder private var passthroughApp: some View {
        FormGroup(title: "Apps", caption: "The app that shows the other computer: Windows App, Citrix Viewer or a virtual machine.") {
            FormRow(label: "Apps", top: true, divider: false) {
                AppChips(apps: $draft.apps, suggestions: KnownPassthroughApps.all.filter {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
                })
            }
        }
        let all = Set(SystemShortcutGroup.allCases)
        FormGroup(title: "macOS shortcuts sent to the app",
                  caption: "\(draft.systemShortcuts.count) of \(all.count) selected. While the app is in front, these keys reach it instead of macOS.",
                  trailing: AnyView(Button(draft.systemShortcuts == all ? "Select None" : "Select All") {
                      draft.systemShortcuts = draft.systemShortcuts == all ? [] : all
                  }.controlSize(.small))) {
            ForEach(Array(SystemShortcutGroup.allCases.enumerated()), id: \.element) { index, group in
                FormRow(divider: index > 0) {
                    Toggle(isOn: Binding(get: { draft.systemShortcuts.contains(group) }, set: { on in
                        if on { draft.systemShortcuts.insert(group) } else { draft.systemShortcuts.remove(group) }
                    })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.title)
                            Text(group.windowsMeaning).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text(group.keys).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        FormGroup(title: "Keys", caption: draft.modifierLayout == .asIs
                  ? "In Windows App and Citrix, ⌘ is usually the Windows key and ⌥ is Alt."
                  : "⌘C is Ctrl+C in the session, as on a PC keyboard; ⌃ becomes the Windows key.") {
            FormRow(divider: false) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send every key straight to the app")
                    Text("Ahead of global shortcuts from Raycast, Alfred or window managers. Only triggers that name this app still run.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Send every key straight to the app", isOn: $draft.captureAllKeys)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            FormRow(label: "Modifier keys") {
                Picker("Modifier keys", selection: $draft.modifierLayout) {
                    ForEach(ModifierLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
        }
    }

    private var pauseNote: String {
        model.config.pauseKeys.map { "Press \($0.displayName) to pause passthrough and get ⌘⇥ back; it resumes when you switch apps." }
            ?? "Entries are tried in order and the first that fits wins."
    }

    // MARK: - config.json and the bottom bar

    private var filePanel: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("This \(draft.isPassthroughApp ? "passthrough app" : "trigger"), as saved in config.json under “\(draft.isPassthroughApp ? "passthrough" : "triggers")”. The form and the file stay in step; MacsBored picks up saved edits to the file.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft.preview, forType: .string)
                    copied = true
                }
                Button("Open File") { model.openConfigFile() }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            Divider()
            ScrollView {
                Text(draft.preview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 190)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onChange(of: draft) { _, _ in copied = false }
    }

    /// MacsPane's editor bar: the extras at the left, then the bin (for a saved one), Cancel and Save.
    private var bottomBar: some View {
        HStack(spacing: 8) {
            let fileButton = Button { withAnimation(.snappy(duration: 0.2)) { showsFile.toggle() } } label: {
                Label("config.json", systemImage: "curlybraces")
            }
            .help("Show this entry as the settings file holds it")
            if showsFile { fileButton.buttonStyle(.borderedProminent) } else { fileButton }
            Spacer()
            if let missing = draft.missing {
                Text(missing).font(.callout).foregroundStyle(.secondary)
            }
            if !isNew { deleteButton }
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            Button("Save") { if let result = draft.result { onSave(result) } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.result == nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// The bin, as in MacsPane: clicked once it turns into a red "bin ?", and a second click deletes.
    @ViewBuilder private var deleteButton: some View {
        if confirmingDelete {
            Button(action: onDelete) {
                HStack(spacing: 1) { Image(systemName: "trash"); Text("?").fontWeight(.semibold) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .help("Click again to delete for good")
            .accessibilityLabel("Confirm delete")
        } else {
            Button { withAnimation(.bouncy(duration: 0.3)) { confirmingDelete = true } } label: {
                Image(systemName: "trash")
            }
            .help(draft.isPassthroughApp ? "Delete this passthrough app" : "Delete this trigger")
            .accessibilityLabel("Delete")
        }
    }
}

private struct FormHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
#endif
