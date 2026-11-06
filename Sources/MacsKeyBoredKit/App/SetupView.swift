#if canImport(AppKit)
import SwiftUI
import MacsKeyBoredCore

/// First run, in one page of MacsPane-style cards: grant Accessibility, pick the apps that should get
/// macOS's shortcuts, and choose the extras. The menu's Setup button opens it again.
struct SetupView: View {
    @ObservedObject var model: MacsKeyBoredModel
    let onDone: () -> Void
    @State private var picked: Set<String> = []

    private var installed: [AppRef] {
        KnownPassthroughApps.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MacsKeyBoredLogo(size: 52).shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacsKeyBored").font(.title2.weight(.semibold))
                    Text("Your Mac's shortcuts, sent to the computer you're remoting into.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 24)

            MenuCard(title: "1 · Permission") {
                CardRow(symbol: model.isAuthorized ? "checkmark.circle.fill" : "hand.raised",
                        tint: model.isAuthorized ? .green : .orange,
                        title: model.isAuthorized ? "Accessibility is on" : "Allow Accessibility",
                        detail: "To see keys before macOS acts on them, and to read whether a window is full screen.") {
                    if !model.isAuthorized {
                        Button("Grant Access") { model.requestAccess() }.buttonStyle(.borderedProminent)
                    }
                }
            }

            MenuCard(title: "2 · Apps that get macOS's shortcuts") {
                if installed.isEmpty {
                    Text("No remote-desktop app found. Add one later from the menu: Passthrough apps › Add an app.")
                        .font(.callout).foregroundStyle(.secondary).padding(12)
                }
                ForEach(Array(installed.enumerated()), id: \.element.id) { index, app in
                    let covered = model.config.profiles.contains { $0.covers(bundleID: app.bundleID) }
                    CardRow(appIcon: AppIcons.icon(bundleID: app.bundleID), title: app.name,
                            detail: covered ? "Already set up" : "⌘⇥, ⌘Space, ⌃←/→, screenshots and more go to the session") {
                        Toggle(app.name, isOn: Binding(
                            get: { covered || picked.contains(app.bundleID) },
                            set: { if $0 { picked.insert(app.bundleID) } else { picked.remove(app.bundleID) } }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        .disabled(covered)
                    }
                    .overlay(alignment: .top) { if index > 0 { Divider() } }
                }
            }

            MenuCard(title: "3 · Extras") {
                CardRow(symbol: "capslock", tint: .accentColor, title: "Caps Lock is Hyper",
                        detail: "Caps Lock holds ⌃⌥⇧⌘, a modifier no app uses, for your own triggers.") {
                    Toggle("Caps Lock is Hyper", isOn: Binding(get: { model.config.hyperKeyEnabled },
                                                               set: { model.setHyperKey($0) }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
                Divider()
                CardRow(symbol: "pause.circle", tint: .accentColor, title: "Pause with \(MacsKeyBoredConfig.defaultPauseKeys.displayName)",
                        detail: "Gives macOS its shortcuts back in a passthrough app until you switch apps.") {
                    EmptyView()
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") {
                    model.addProfiles(for: installed.filter { picked.contains($0.bundleID) })
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            picked = Set(installed.map(\.bundleID))
        }
    }
}
#endif
