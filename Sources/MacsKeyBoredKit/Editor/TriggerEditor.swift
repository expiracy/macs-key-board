#if canImport(AppKit)
import SwiftUI
import MacsKeyBoredCore

/// A trigger's editor: its keys (in the toolbar, where MacsPane puts a preset's shortcut), what it
/// does, where it works and when.
struct TriggerEditor: View {
    @State var draft: Trigger
    let isNew: Bool
    let model: MacsKeyBoredModel
    let onSave: (Trigger) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        EditorPage {
            EditorToolbar(title: isNew ? "New trigger" : "Trigger", symbol: draft.action.kind.symbol,
                          name: $draft.name, isNew: isNew, canSave: draft.shortcut != nil,
                          saveHelp: draft.shortcut == nil ? "Give it keys first" : "Save",
                          onDelete: onDelete, onCancel: onCancel, onSave: { onSave(draft) }) {
                KeyRecorder(keys: $draft.shortcut, model: model)
            }
        } cards: {
            actionCard
            AppsCard(title: "Where", apps: $draft.apps,
                     emptyLine: "Everywhere, except inside a passthrough app (its keys belong to the session). Add apps to have it work only there, a passthrough app included.",
                     suggestions: [])
            ConditionsCard(conditions: $draft.conditions, emptyLine: "Always.")
            if let clash {
                Label(clash, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Saving takes the keys from another trigger that has them in the same place.
    private var clash: String? {
        guard let keys = draft.shortcut,
              let other = model.config.triggers.first(where: { $0.id != draft.id && $0.shortcut == keys && $0.apps == draft.apps })
        else { return nil }
        return "Saving takes \(keys.displayName) from “\(other.name)”."
    }

    private var actionCard: some View {
        MenuCard(title: "Does") {
            CardRow(symbol: draft.action.kind.symbol, tint: .accentColor, title: "Action") {
                Picker("Action", selection: Binding(get: { draft.action.kind }, set: { kind in
                    guard kind != draft.action.kind else { return }
                    if draft.name == draft.action.kind.title { draft.name = kind.title }
                    draft.action = kind.blank
                })) {
                    ForEach(TriggerAction.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Divider()
            detail
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var detail: some View {
        switch draft.action {
        case let .sendShortcut(keys):
            HStack {
                Text("Press")
                KeyRecorder(keys: Binding(get: { keys }, set: { if let new = $0 { draft.action = .sendShortcut(new) } }),
                            placeholder: "Choose keys", allowPlain: true, model: model)
                Text("instead").foregroundStyle(.secondary)
            }
        case let .openApp(app):
            HStack {
                if let icon = AppIcons.icon(bundleID: app.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                Text(app.name)
                Spacer()
                Button("Choose…") { AppChooser.choose { draft.action = .openApp($0) } }
            }
        case let .openURL(url):
            TextField("https://… or /path/to/file", text: Binding(get: { url }, set: { draft.action = .openURL($0) }))
                .textFieldStyle(.roundedBorder)
        case let .runShell(command):
            VStack(alignment: .leading, spacing: 4) {
                TextField("open -a Terminal ~", text: Binding(get: { command }, set: { draft.action = .runShell($0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Runs with /bin/zsh -lc in the background; output is discarded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case let .typeText(text):
            TextEditor(text: Binding(get: { text }, set: { draft.action = .typeText($0) }))
                .font(.body)
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
        case .togglePause:
            Text("Pauses passthrough in the app in front, or resumes it.").foregroundStyle(.secondary)
        case .toggleKeepAwake:
            Text("Switches Keep awake on or off.").foregroundStyle(.secondary)
        }
    }
}
#endif
