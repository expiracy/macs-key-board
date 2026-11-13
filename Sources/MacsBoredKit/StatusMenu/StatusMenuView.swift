#if canImport(AppKit)
import SwiftUI

/// What the menu-bar dropdown shows and does. Rebuilt on open, after every click that leaves it
/// open, and once a second while it is open (what is in front changes under it).
final class StatusMenuModel: ObservableObject {
    @Published private(set) var content = StatusMenuContent()
    /// Where the menu-bar icon sits along the bubble's top edge, so its nub points at it.
    @Published var nubX: CGFloat?
    /// The row whose trash was clicked once: its bin is now a red "bin?" pill and a second click deletes.
    @Published var confirmingTrash: String?
    let name: String
    var onSetup: () -> Void = {}
    var onNew: () -> Void = {}
    var onQuit: () -> Void = {}
    /// Set by the panel's owner; commands close the dropdown before they act.
    var onClose: () -> Void = {}
    private let assemble: () -> StatusMenuContent

    init(name: String, assemble: @escaping () -> StatusMenuContent) {
        self.name = name
        self.assemble = assemble
        refresh()
    }

    func refresh() {
        content = assemble()
    }

    func pick(_ entry: StatusMenuEntry, index: Int) {
        entry.select?(index)
        refresh()
    }

    func runTrash(_ entry: StatusMenuEntry) {
        guard confirmingTrash == entry.id else { confirmingTrash = entry.id; return }
        confirmingTrash = nil
        entry.trash?.action()
        refresh()
    }

    func cancelTrash(_ entry: StatusMenuEntry) {
        if confirmingTrash == entry.id { confirmingTrash = nil }
    }

    func runSecondary(_ entry: StatusMenuEntry) {
        guard let secondary = entry.secondary else { return }
        onClose()
        secondary.action()
    }

    func run(_ entry: StatusMenuEntry) {
        guard let action = entry.action else { return }
        switch entry.kind {
        case .toggle, .live, .choice:
            action()
            refresh()
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        case .command where entry.keepsOpen:
            action()
            refresh()
        case .command, .warning:
            onClose()
            action()
        }
    }
}

/// The menu-bar icon's dropdown, drawn as MacsPane draws its own: a bubble whose nub points up at
/// the icon; the mark, the name and the main switch; then rounded cards, each under a small title:
/// what is happening now with its one button, any warning with its fix, the general switches and
/// the titled lists. Rows lead with a tinted icon tile or the app's own icon. Setup and Quit sit at the foot.
struct StatusMenuView: View {
    @ObservedObject var model: StatusMenuModel
    @State private var hoveredRow: String?
    @State private var hoveredTrash: String?

    /// MacsPane's dropdown metrics.
    enum Metric {
        static let width: CGFloat = 360
        static let edge: CGFloat = 12
        static let row: CGFloat = 38
        static let corner: CGFloat = 12
        static let tile: CGFloat = 24
        /// A list taller than this many rows scrolls; the half row peeking out says there is more.
        static let visibleRows: CGFloat = 3.5
    }

    var body: some View {
        let content = model.content
        VStack(alignment: .leading, spacing: 14) {
            header(content)
            if !content.live.isEmpty { liveCard(content.live) }
            ForEach(content.warnings) { warningCard($0) }
            if !content.toggles.isEmpty {
                MenuCard(title: "General") { rows(content.toggles) }
            }
            ForEach(content.groups) { groupCard($0) }
            footer
        }
        .padding(Metric.edge)
        .padding(.top, SpeechBubbleShape.standardNub.height)
        .frame(width: Metric.width)
        .background(SpeechBubbleShape(nubX: model.nubX).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nubX: model.nubX).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Bands

    private func header(_ content: StatusMenuContent) -> some View {
        HStack(spacing: 10) {
            MacsBoredLogo(size: 32)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name).font(.system(size: 15, weight: .semibold))
                if let line = content.liveFact ?? content.primary?.title {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let primary = content.primary, case let .toggle(isOn, _, _) = primary.kind {
                switchControl(primary, isOn: isOn)
            }
        }
        .padding(.horizontal, 4)
    }

    /// What is happening now, laid out as MacsPane's Undo prompt is: its icon, what and why, one button.
    private func liveCard(_ live: [StatusMenuEntry]) -> some View {
        MenuCard(title: "Now") {
            ForEach(live) { entry in
                if case let .live(fact, actionTitle, accent) = entry.kind {
                    HStack(spacing: 10) {
                        if let appIcon = entry.appIcon {
                            Image(nsImage: appIcon).resizable().interpolation(.high).frame(width: 30, height: 30)
                        } else {
                            IconTile(symbol: entry.symbol ?? "keyboard", tint: accent ? .accentColor : .secondary, size: 30)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.headline).lineLimit(1)
                            if !fact.isEmpty {
                                Text(fact).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        if let actionTitle {
                            Button(actionTitle) { model.run(entry) }
                                .buttonStyle(.borderedProminent)
                                .tint(accent ? .accentColor : .gray)
                                .controlSize(.small)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func warningCard(_ entry: StatusMenuEntry) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "exclamationmark.triangle.fill", tint: .orange, size: Metric.tile)
            Text(entry.title).font(.callout.weight(.medium)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if case let .warning(actionTitle) = entry.kind, let actionTitle {
                Button(actionTitle) { model.run(entry) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }

    private func groupCard(_ group: StatusMenuGroup) -> some View {
        MenuCard(title: group.title) {
            if group.rows.isEmpty, let empty = group.empty {
                Text(empty)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if CGFloat(group.rows.count) > Metric.visibleRows {
                ScrollView { rows(group.rows) }
                    .frame(height: Metric.visibleRows * Metric.row)
            } else {
                rows(group.rows)
            }
            if !group.actions.isEmpty {
                Divider()
                rows(group.actions)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("New", symbol: "plus", key: nil, action: model.onNew)
            footerButton("Setup", symbol: "sparkles", key: nil, action: model.onSetup)
            footerButton("Quit", symbol: "power", key: "⌘Q", action: model.onQuit)
        }
        .controlSize(.large)
    }

    private func footerButton(_ title: String, symbol: String, key: String?,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title)
                if let key { Text(key).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(title)
    }

    // MARK: - Rows

    private func rows(_ entries: [StatusMenuEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry)
                    .overlay(alignment: .top) { if index > 0 { Divider() } }
            }
        }
    }

    @ViewBuilder private func row(_ entry: StatusMenuEntry) -> some View {
        switch entry.kind {
        case let .toggle(isOn, disabled, _):
            HStack(spacing: 10) {
                icon(entry, tint: .secondary)
                Text(entry.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let trailing = entry.trailing {
                    Text(trailing).font(.callout.monospacedDigit())
                        .foregroundStyle(isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
                if let secondary = entry.secondary {
                    secondaryButton(entry, secondary, hovered: hoveredRow == entry.id)
                }
                if entry.trash != nil { trashButton(entry).padding(.leading, -8) }
                switchControl(entry, isOn: isOn)
            }
            .padding(.horizontal, 10)
            .frame(height: Metric.row)
            .background(Color.primary.opacity(hoveredRow == entry.id ? 0.04 : 0))
            .onHover { hover(entry, $0) }
            .disabled(disabled)
        case let .choice(options, selected):
            HStack(spacing: 10) {
                icon(entry, tint: .secondary)
                Text(entry.title).lineLimit(1)
                Spacer(minLength: 4)
                Picker(entry.title, selection: Binding(get: { selected }, set: { model.pick(entry, index: $0) })) {
                    ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: Metric.row)
        case let .command(danger):
            commandRow(entry, danger: danger)
        case .live, .warning:
            EmptyView()
        }
    }

    /// A row you click. A command that adds something (a plus) is drawn in the accent, as MacsPane draws
    /// its "New preset".
    private func commandRow(_ entry: StatusMenuEntry, danger: Bool) -> some View {
        let hovered = hoveredRow == entry.id
        let adds = entry.symbol == "plus" || entry.symbol?.hasSuffix(".badge.plus") == true
        let label = HStack(spacing: 10) {
            icon(entry, tint: adds ? .accentColor : .secondary)
            Text(entry.title).lineLimit(1).truncationMode(.tail)
                .fontWeight(adds ? .medium : .regular)
                .foregroundStyle(danger ? AnyShapeStyle(.red) : adds ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
            if let trailing = entry.trailing {
                Text(trailing).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .padding(.leading, 10)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        return HStack(spacing: 0) {
            Button { model.run(entry) } label: { label }
                .buttonStyle(.plain)
            if let secondary = entry.secondary {
                secondaryButton(entry, secondary, hovered: hovered)
                    .padding(.trailing, entry.trash == nil ? 6 : 0)
            }
            if entry.trash != nil {
                trashButton(entry).padding(.trailing, 6)
            } else if entry.secondary == nil {
                Spacer().frame(width: 10)
            }
        }
        .frame(height: Metric.row)
        .background(Color.primary.opacity(hovered ? 0.06 : 0))
        .onHover { hover(entry, $0) }
    }

    private func hover(_ entry: StatusMenuEntry, _ inside: Bool) {
        hoveredRow = inside ? entry.id : (hoveredRow == entry.id ? nil : hoveredRow)
        if !inside { withAnimation(.bouncy(duration: 0.3)) { model.cancelTrash(entry) } }
    }

    private func secondaryButton(_ entry: StatusMenuEntry, _ secondary: (symbol: String, help: String, action: () -> Void),
                                 hovered: Bool) -> some View {
        Button { model.runSecondary(entry) } label: {
            Image(systemName: secondary.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(hovered ? 0.13 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(secondary.help)
        .accessibilityLabel("\(secondary.help) \(entry.title)")
    }

    /// MacsPane's bin: clicked once it grows into a red "bin ?" pill, and a second click deletes.
    private func trashButton(_ entry: StatusMenuEntry) -> some View {
        let hot = hoveredTrash == entry.id
        let asking = model.confirmingTrash == entry.id
        return Button { withAnimation(.bouncy(duration: 0.3, extraBounce: 0.15)) { model.runTrash(entry) } } label: {
            HStack(spacing: 1) {
                Image(systemName: "trash")
                if asking {
                    Text("?").transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(asking ? AnyShapeStyle(Color.white) : hot ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            .frame(width: asking ? 44 : 26, height: asking ? 22 : 24)
            .background {
                RoundedRectangle(cornerRadius: asking ? 11 : 6, style: .continuous)
                    .fill(Color.red.opacity(asking ? 1 : hot ? 0.13 : 0))
            }
            .padding(.trailing, asking ? 4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredTrash = inside ? entry.id : (hoveredTrash == entry.id ? nil : hoveredTrash) }
        .help(asking ? "Click again to delete" : entry.trash?.help ?? "Delete")
        .accessibilityLabel(asking ? "Confirm delete \(entry.title)" : "Delete \(entry.title)")
    }

    private func switchControl(_ entry: StatusMenuEntry, isOn: Bool) -> some View {
        Toggle(entry.title, isOn: Binding(get: { isOn }, set: { _ in model.run(entry) }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }

    @ViewBuilder private func icon(_ entry: StatusMenuEntry, tint: Color) -> some View {
        if let appIcon = entry.appIcon {
            Image(nsImage: appIcon).resizable().interpolation(.high)
                .frame(width: Metric.tile, height: Metric.tile)
                .frame(width: Metric.tile + 2)
        } else {
            IconTile(symbol: entry.symbol ?? "circle", tint: tint, size: Metric.tile)
                .frame(width: Metric.tile + 2)
        }
    }
}

#endif
