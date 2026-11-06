#if canImport(AppKit)
import SwiftUI
import MacsKeyBoredCore

/// A passthrough profile's editor: its apps, when it acts (conditions), which of macOS's shortcuts go
/// to the app, and how the keys travel.
struct ProfileEditor: View {
    @State var draft: PassthroughProfile
    let isNew: Bool
    let model: MacsKeyBoredModel
    let onSave: (PassthroughProfile) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        EditorPage {
            EditorToolbar(title: isNew ? "New passthrough" : "Passthrough", symbol: "command",
                          name: $draft.name, isNew: isNew, canSave: !draft.apps.isEmpty,
                          saveHelp: draft.apps.isEmpty ? "Add an app first" : "Save",
                          onDelete: onDelete, onCancel: onCancel, onSave: { onSave(draft) }) {
                Toggle("On", isOn: $draft.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Switch this passthrough on or off without deleting it")
            }
        } cards: {
            AppsCard(title: "Apps", apps: $draft.apps,
                     emptyLine: "Add the app that shows the other computer: Windows App, Citrix Viewer, a VM.",
                     suggestions: KnownPassthroughApps.all.filter {
                         NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
                     })
            ConditionsCard(conditions: $draft.conditions,
                           emptyLine: "Always, whenever one of these apps is in front. Add a condition to pass keys through only in full screen, say, or only for one desktop by its window title.")
            shortcutsCard
            keysCard
            Text(footnote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var footnote: String {
        let pause = model.config.pauseKeys.map { "Press \($0.displayName) to pause passthrough and get ⌘⇥ back; it resumes when you switch apps. " } ?? ""
        return pause + "Profiles are tried in order and the first that fits the app in front wins. Apps' own menu shortcuts (⌘Q, ⌘H in Windows App itself) still go to the app's menus."
    }

    private var shortcutsCard: some View {
        let all = Set(SystemShortcutGroup.allCases)
        let trailing = AnyView(Button(draft.systemShortcuts == all ? "None" : "All") {
            draft.systemShortcuts = draft.systemShortcuts == all ? [] : all
        }
        .buttonStyle(.link).controlSize(.small))
        return MenuCard(title: "macOS shortcuts that go to the app instead", trailing: trailing) {
            ForEach(Array(SystemShortcutGroup.allCases.enumerated()), id: \.element) { index, group in
                CardRow(symbol: group.symbol, tint: draft.systemShortcuts.contains(group) ? .accentColor : .secondary,
                        title: group.title, detail: "\(group.keys)  ·  \(group.windowsMeaning)") {
                    Toggle(group.title, isOn: Binding(
                        get: { draft.systemShortcuts.contains(group) },
                        set: { on in
                            if on { draft.systemShortcuts.insert(group) } else { draft.systemShortcuts.remove(group) }
                        }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
                .overlay(alignment: .top) { if index > 0 { Divider() } }
            }
        }
    }

    private var keysCard: some View {
        MenuCard(title: "Keys") {
            CardRow(symbol: "arrow.right.to.line", tint: .accentColor, title: "Send every key straight to the app",
                    detail: "Ahead of other apps' global shortcuts (Raycast, Alfred, window managers). Only your triggers that name this app still run.") {
                Toggle("Send every key straight to the app", isOn: $draft.captureAllKeys)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            Divider()
            CardRow(symbol: "command", tint: .accentColor, title: "Modifier keys",
                    detail: draft.modifierLayout == .asIs
                        ? "The app maps them: in Windows App and Citrix ⌘ is usually the Windows key and ⌥ is Alt."
                        : "⌘C is Ctrl+C in the session, as on a PC keyboard; ⌃ becomes the Windows key.") {
                Picker("Modifier keys", selection: $draft.modifierLayout) {
                    ForEach(ModifierLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}
#endif
