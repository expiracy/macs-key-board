#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// One editor window at a time, opened from a row's pencil or the menu's New.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onClose: () -> Void = {}

    /// A window of `size`, or, with `fitsContent`, one that takes the content's own size and follows it
    /// as it grows and shrinks.
    func show<Content: View>(title: String, size: CGSize, fitsContent: Bool = false, @ViewBuilder content: () -> Content) {
        close()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: content())
        if fitsContent {
            host.sizingOptions = [.preferredContentSize]
            // The content draws its own title row under the window's buttons, so the window's size is
            // exactly the content's, with no room kept for a title bar.
            host.safeAreaRegions = []
        }
        window.contentViewController = host
        if !fitsContent { window.setContentSize(size) }
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

// MARK: - Form pieces, one look for every page

/// The editor's sizes, set to MacsPane's editor: large controls on 44-point rows.
enum FormMetric {
    static let label: CGFloat = 120
    static let field: CGFloat = 300
    static let row: CGFloat = 44
}

/// A titled group of rows on a white panel, with a quiet line under it.
struct FormGroup<Content: View>: View {
    var title: String?
    var caption: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 10)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            if let caption, !caption.isEmpty {
                Text(caption).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }
        }
    }
}

/// A row: its label in the one left-hand column, then its control.
struct FormRow<Content: View>: View {
    var label: String?
    var top = false
    var divider = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: top ? .top : .center, spacing: 8) {
            if let label {
                Text(label).frame(width: FormMetric.label, alignment: .leading)
                    .frame(minHeight: 28)
            }
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: FormMetric.row, alignment: .leading)
        .overlay(alignment: .top) { if divider { Divider() } }
    }
}

/// The box every single-value control sits in: a text field's border, height and width.
struct FieldBox<Content: View>: View {
    var active = false
    var problem = false
    var width: CGFloat = FormMetric.field
    @ViewBuilder var content: Content
    @Environment(\.controlSize) private var controlSize

    /// A rounded text field's height at the control size around it.
    private var height: CGFloat {
        switch controlSize {
        case .large, .extraLarge: 28
        case .small: 19
        case .mini: 16
        default: 22
        }
    }

    var body: some View {
        HStack(spacing: 4) { content }
            .padding(.horizontal, 6)
            .frame(width: width, height: height, alignment: .leading)
            .background {
                // An empty text field underneath, so this box has exactly the name field's look.
                TextField("", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .focusable(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                if active || problem {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(problem ? Color.orange : Color.accentColor, lineWidth: 2)
                        .padding(-1)
                }
            }
            .contentShape(Rectangle())
    }
}

/// A key drawn as a keycap.
struct KeyCap: View {
    let text: String
    var held = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 6)
            .frame(minWidth: 21, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .opacity(held ? 0.5 : 1)
    }
}

extension KeyCombo {
    /// Each modifier and the key, as keycaps show them.
    var caps: [String] {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1) + [keyName]
    }
}

/// A key recorder in a field: the keys as keycaps, or, once clicked, the modifiers you hold as you
/// hold them, waiting for a key. esc stops; ⌫ alone clears it.
struct KeyRecorderField: View {
    @Binding var keys: KeyCombo?
    @Binding var recording: Bool
    /// Accept keys without ⌘, ⌃ or ⌥ (for keys pressed instead, where ↖ alone is fine).
    var allowPlain = false
    var placeholder = "Click to record"
    var width: CGFloat = FormMetric.field
    /// Keep listening after each set of keys, for adding several in a row; esc or a click stops.
    var keepsRecording = false
    var onRefused: (String) -> Void = { _ in }
    let model: MacsBoredModel
    @State private var held: KeyCombo.Modifiers = []
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            FieldBox(active: recording, width: width) {
                if recording {
                    ForEach(KeyCombo(keyCode: 0, modifiers: held).caps.dropLast(), id: \.self) { KeyCap(text: $0, held: true) }
                    if held.isEmpty { Text("Press the keys…").foregroundStyle(.secondary).padding(.leading, 3) }
                    Spacer(minLength: 0)
                    Circle().fill(Color.red).frame(width: 6, height: 6).padding(.trailing, 3)
                } else if let keys {
                    ForEach(Array(keys.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                    Spacer(minLength: 0)
                } else {
                    Text(placeholder).foregroundStyle(.secondary).padding(.leading, 3)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .help(recording ? "Hold the modifiers, then press a key" : "Click, then press the keys")
        .accessibilityLabel("Keys: \(keys?.displayName ?? "none")")
        .onDisappear { stop() }
        .onChange(of: recording) { _, now in if !now { stop() } }
    }

    private func start() {
        recording = true
        held = []
        model.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = FlagBits.modifiers(UInt64(event.modifierFlags.rawValue))
            if event.type == .flagsChanged { held = modifiers; return nil }
            if event.keyCode == KeyCombo.Code.escape && modifiers.isEmpty { stop(); return nil }
            if event.keyCode == 51 && modifiers.isEmpty { keys = nil; stop(); return nil }
            let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers, character: event.charactersIgnoringModifiers)
            if combo.isUsableAsTrigger || allowPlain {
                keys = combo
                if keepsRecording { held = [] } else { stop() }
            } else {
                onRefused("“\(combo.keyName)” on its own would take over typing. Hold ⌘, ⌃ or ⌥ with it, or use an F-key.")
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { model.isRecording = false; recording = false }
        held = []
    }
}

/// Lays its children out in rows, wrapping, for app chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// The apps as chips with a remove button, then a menu to add one.
struct AppChips: View {
    @Binding var apps: [AppRef]
    let suggestions: [AppRef]
    var suggestionsTitle = "Suggested"

    var body: some View {
        FlowLayout {
            ForEach(apps) { app in
                HStack(spacing: 4) {
                    if let icon = AppIcons.icon(bundleID: app.bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(AppIcons.name(app)).lineLimit(1)
                    Button { apps.removeAll { $0.id == app.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 16, height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(AppIcons.name(app))")
                }
                .padding(.leading, 8).padding(.trailing, 4)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            Menu {
                let available = suggestions.filter { !apps.contains($0) }
                if !available.isEmpty {
                    Section(suggestionsTitle) { ForEach(available) { app in Button(AppIcons.name(app)) { apps.append(app) } } }
                }
                Divider()
                Button("Choose an app…") { AppChooser.choose { app in if !apps.contains(app) { apps.append(app) } } }
            } label: {
                Label("Add App", systemImage: "plus")
            }
            .fixedSize()
        }
    }
}

/// Only-if and unless conditions, any number, combined by all or any.
struct ConditionRows: View {
    @Binding var conditions: ConditionSet

    var body: some View {
        ForEach(Array(conditions.conditions.enumerated()), id: \.element.id) { index, condition in
            FormRow(divider: index > 0) { row(index: index, condition: condition) }
        }
        FormRow(divider: !conditions.conditions.isEmpty) {
            Menu {
                ForEach(Array(Condition.Kind.templates.enumerated()), id: \.offset) { _, kind in
                    Button { conditions.conditions.append(Condition(kind)) } label: { Label(kind.title, systemImage: kind.symbol) }
                }
            } label: {
                Label("Add Condition", systemImage: "plus")
            }
            .fixedSize()
            Spacer()
            if conditions.conditions.count > 1 {
                Text("Match").font(.caption).foregroundStyle(.secondary)
                Picker("Match", selection: $conditions.match) {
                    Text("All").tag(ConditionMatch.all)
                    Text("Any").tag(ConditionMatch.any)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }

    private func row(index: Int, condition: Condition) -> some View {
        let binding = Binding<Condition>(
            get: { conditions.conditions.indices.contains(index) ? conditions.conditions[index] : condition },
            set: { if conditions.conditions.indices.contains(index) { conditions.conditions[index] = $0 } })
        return HStack(spacing: 8) {
            Picker("", selection: binding.negated) {
                Text("Only if").tag(false)
                Text("Unless").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Text(condition.kind.title.lowercased()).lineLimit(1)
            parameter(binding)
            Spacer(minLength: 4)
            Button { conditions.conditions.removeAll { $0.id == condition.id } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this condition")
        }
    }

    @ViewBuilder private func parameter(_ condition: Binding<Condition>) -> some View {
        switch condition.wrappedValue.kind {
        case let .windowTitleContains(text):
            TextField("Text", text: Binding(get: { text }, set: { condition.wrappedValue.kind = .windowTitleContains($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        case let .timeBetween(start, end):
            HStack(spacing: 4) {
                timePicker(start) { condition.wrappedValue.kind = .timeBetween(start: $0, end: end) }
                Text("to").foregroundStyle(.secondary)
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
