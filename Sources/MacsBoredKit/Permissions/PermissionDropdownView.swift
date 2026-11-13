#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// The permission dropdown, hanging under System Settings: the app's icon and two numbered steps (drag
/// the icon into the list above, then switch the app on), with a line saying it closes by itself. A
/// spinner waits for the switch; a green tick replaces it once access is on, and the dropdown closes. The ⋯ menu holds the rare things: reopening the pane, replacing a stale
/// entry, closing.
struct PermissionDropdownView: View {
    let grant: PermissionGrant
    let appName: String
    let appURL: URL
    @ObservedObject var model: PermissionGrantModel
    @State private var hovered = false

    static let width: CGFloat = 420
    private static let nub = SpeechBubbleShape.standardNub

    private var canDragApp: Bool { appURL.pathExtension == "app" }

    var body: some View {
        HStack(spacing: 14) {
            appIcon
            if model.granted {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(appName) can see your keys").font(.headline)
                    Text("You're all set. This closes now.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Drag this icon into the list above.")
                    step(2, "Switch \(appName) on in that list.")
                    Text("This closes by itself as soon as it's on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
            }
            Spacer(minLength: 0)
            status
            if !model.granted { moreMenu }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14 + Self.nub.height)
        .padding(.bottom, 14)
        .frame(width: Self.width)
        .background(SpeechBubbleShape(nub: Self.nub).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nub: Self.nub).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: model.granted)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The app's icon, and the thing you drag: its payload is the app bundle itself.
    @ViewBuilder private var appIcon: some View {
        let image = MacsBoredLogo(size: 52)
            .scaleEffect(hovered && !model.granted ? 1.06 : 1)
            .shadow(color: .black.opacity(hovered ? 0.25 : 0.12), radius: hovered ? 6 : 3, y: 2)
            .animation(.easeOut(duration: 0.12), value: hovered)
        if canDragApp && !model.granted {
            image
                .onDrag { NSItemProvider(contentsOf: appURL) ?? NSItemProvider() }
                .onHover { inside in
                    hovered = inside
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .help("Drag \(appName) into the \(grant.title) list")
                .accessibilityLabel("\(appName), drag into the \(grant.title) list")
        } else {
            image.accessibilityHidden(true)
        }
    }

    @ViewBuilder private var status: some View {
        if model.granted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Access granted")
        } else {
            ProgressView()
                .controlSize(.small)
                .help("Waiting for \(appName) to be switched on")
                .accessibilityLabel("Waiting for access")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Show the \(grant.title) list again", action: model.openSettings)
            Button("Start over", action: model.startOver)
                .help(grant.staleEntryHint(appName: appName))
            Divider()
            Button("Close", action: model.close)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

#endif
