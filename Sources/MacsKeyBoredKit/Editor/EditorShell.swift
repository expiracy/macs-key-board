#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsKeyBoredCore

/// One editor window at a time, opened from a row's pencil or a "New…" command: a plain window whose
/// SwiftUI content carries MacsPane's floating toolbar at the top and cards below.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onClose: () -> Void = {}

    func show<Content: View>(title: String, size: CGSize, @ViewBuilder content: () -> Content) {
        close()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.setContentSize(size)
        window.minSize = NSSize(width: size.width, height: 420)
        window.center()
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
        onClose()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose()
    }
}

/// MacsPane's editor toolbar: a solid rounded bar with its own shadow, holding what is being edited
/// and its name, the editor's own controls, then the bin (for a saved one), Cancel and Save.
struct EditorToolbar<Middle: View>: View {
    let title: String
    let symbol: String
    @Binding var name: String
    let isNew: Bool
    var canSave = true
    var saveHelp = "Save"
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var middle: Middle
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .fixedSize()
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 200)
            Divider().frame(height: 22)
            middle
            Spacer(minLength: 0)
            if !isNew { deleteButton }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .help(saveHelp)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    /// The bin, as in the menu: clicked once it grows into a red "bin ?", and a second click deletes.
    @ViewBuilder private var deleteButton: some View {
        if confirmingDelete {
            Button(action: onDelete) {
                HStack(spacing: 1) { Image(systemName: "trash"); Text("?").fontWeight(.semibold) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .help("Click again to delete for good")
        } else {
            Button { withAnimation(.bouncy(duration: 0.3)) { confirmingDelete = true } } label: {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
    }
}

/// The editor's page: the toolbar pinned at the top, the cards scrolling under it.
struct EditorPage<Toolbar: View, Cards: View>: View {
    @ViewBuilder var toolbar: Toolbar
    @ViewBuilder var cards: Cards

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 14)
                .padding(.top, 34)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { cards }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A shortcut's chip, as MacsPane's: "Add keys", the keys it has with a clear button, or, once
/// clicked, a dashed prompt waiting for them. esc keeps what it had; ⌫ alone clears it.
struct KeyRecorder: View {
    @Binding var keys: KeyCombo?
    var placeholder = "Add keys"
    /// Accept keys without ⌘, ⌃ or ⌥ (for "send these keys", where ↖ alone is fine).
    var allowPlain = false
    let model: MacsKeyBoredModel
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 4) {
            Button { recording ? stop() : start() } label: { label }
                .buttonStyle(.plain)
                .help(recording ? "Press the keys; esc keeps what was there, ⌫ clears it" : "Click, then press the keys")
            if let keys, !recording {
                Button { self.keys = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(keys.displayName)")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .fixedSize()
        .onDisappear { stop() }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
            if recording {
                Text(hint ?? "Type the keys")
            } else if let keys {
                Text(keys.displayName).monospacedDigit()
            } else {
                Text(placeholder)
            }
        }
        .foregroundStyle(recording ? Color.accentColor : .primary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(recording ? 0.04 : 0.07)))
        .overlay {
            if recording {
                Capsule().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .contentShape(Capsule())
    }

    private func start() {
        recording = true
        hint = nil
        model.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = FlagBits.modifiers(UInt64(event.modifierFlags.rawValue))
            if event.keyCode == KeyCombo.Code.escape && modifiers.isEmpty { stop(); return nil }
            if event.keyCode == 51 && modifiers.isEmpty { keys = nil; stop(); return nil }
            let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers,
                                 character: event.charactersIgnoringModifiers)
            if combo.isUsableAsTrigger || allowPlain {
                keys = combo
                stop()
            } else {
                hint = "Add ⌘, ⌃ or ⌥ (or use an F-key)"
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { model.isRecording = false }
        recording = false
    }
}

/// A card of apps: each with its icon and a remove button, then a menu to add one.
struct AppsCard: View {
    let title: String
    @Binding var apps: [AppRef]
    var emptyLine: String
    var suggestions: [AppRef]

    var body: some View {
        MenuCard(title: title) {
            if apps.isEmpty {
                Text(emptyLine).font(.callout).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                CardRow(symbol: "app", appIcon: AppIcons.icon(bundleID: app.bundleID), title: app.name,
                        detail: app.bundleID) {
                    Button { apps.removeAll { $0.id == app.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.name)")
                }
                .overlay(alignment: .top) { if index > 0 { Divider() } }
            }
            Divider()
            HStack {
                Menu {
                    let running = NSWorkspace.shared.runningApplications
                        .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                        .compactMap { app -> AppRef? in
                            guard let id = app.bundleIdentifier else { return nil }
                            return AppRef(bundleID: id, name: app.localizedName ?? id)
                        }
                    let available = suggestions.filter { app in !apps.contains(app) }
                    if !available.isEmpty {
                        Section("Suggested") { ForEach(available) { app in Button(app.name) { add(app) } } }
                    }
                    Section("Open now") {
                        ForEach(running.filter { !apps.contains($0) }) { app in Button(app.name) { add(app) } }
                    }
                    Divider()
                    Button("Choose an app…") { AppChooser.choose { add($0) } }
                } label: {
                    Label("Add an app", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    private func add(_ app: AppRef) {
        if !apps.contains(app) { apps.append(app) }
    }
}

/// BetterTouchTool-style conditions: "All of these" or "Any of these", then each one with is/isn't,
/// what it tests and what it needs (text, times), and a menu to add another.
struct ConditionsCard: View {
    @Binding var conditions: ConditionSet
    var emptyLine: String

    var body: some View {
        MenuCard(title: "When", trailing: conditions.conditions.count > 1 ? AnyView(matchPicker) : nil) {
            if conditions.conditions.isEmpty {
                Text(emptyLine).font(.callout).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(conditions.conditions.enumerated()), id: \.element.id) { index, condition in
                row(index: index, condition: condition)
                    .overlay(alignment: .top) { if index > 0 { Divider() } }
            }
            Divider()
            HStack {
                Menu {
                    ForEach(Array(Condition.Kind.templates.enumerated()), id: \.offset) { _, kind in
                        Button { conditions.conditions.append(Condition(kind)) } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add a condition", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    private var matchPicker: some View {
        Picker("Match", selection: $conditions.match) {
            Text("All of these").tag(ConditionMatch.all)
            Text("Any of these").tag(ConditionMatch.any)
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
    }

    private func row(index: Int, condition: Condition) -> some View {
        let binding = Binding<Condition>(
            get: { conditions.conditions.indices.contains(index) ? conditions.conditions[index] : condition },
            set: { if conditions.conditions.indices.contains(index) { conditions.conditions[index] = $0 } })
        return HStack(spacing: 10) {
            IconTile(symbol: condition.kind.symbol, tint: .accentColor, size: 24)
            Picker("", selection: binding.negated) {
                Text("Only if").tag(false)
                Text("Unless").tag(true)
            }
            .labelsHidden().fixedSize()
            Text(condition.kind.title.lowercased()).lineLimit(1)
            parameter(binding)
            Spacer(minLength: 4)
            Button { conditions.conditions.removeAll { $0.id == condition.id } } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this condition")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    @ViewBuilder private func parameter(_ condition: Binding<Condition>) -> some View {
        switch condition.wrappedValue.kind {
        case let .windowTitleContains(text):
            TextField("Text", text: Binding(get: { text }, set: { condition.wrappedValue.kind = .windowTitleContains($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
        case let .timeBetween(start, end):
            HStack(spacing: 4) {
                timePicker(start) { condition.wrappedValue.kind = .timeBetween(start: $0, end: end) }
                Text("and")
                timePicker(end) { condition.wrappedValue.kind = .timeBetween(start: start, end: $0) }
            }
        default:
            EmptyView()
        }
    }

    private func timePicker(_ minutes: Int, set: @escaping (Int) -> Void) -> some View {
        let date = Binding<Date>(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60)) },
            set: { value in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            })
        return DatePicker("", selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden().fixedSize()
    }
}
#endif
