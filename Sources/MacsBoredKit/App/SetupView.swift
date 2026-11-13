#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// First-time setup, laid out as MacsPane's: the mark and name over a sidebar of numbered steps on
/// the system sidebar material, the step's title and one line under it, the step itself, and Back ·
/// progress dots · Continue at the foot. Two of the steps are hands-on: a sample remote session to
/// try passthrough on, and sample triggers.
struct SetupView: View {
    enum Step: Int, CaseIterable {
        case welcome, access, passthrough, trigger, apps

        var sidebar: String {
            switch self {
            case .welcome: "Welcome"
            case .access: "Accessibility"
            case .passthrough: "Try passthrough"
            case .trigger: "Try a trigger"
            case .apps: "Choose your apps"
            }
        }

        var title: String {
            switch self {
            case .welcome: "Welcome to MacsBored"
            case .access: "Allow Accessibility"
            case .passthrough: "Try passthrough"
            case .trigger: "Try a trigger"
            case .apps: "Choose your apps"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Your Mac's shortcuts, sent to the computer you're remoting into."
            case .access: "The one permission MacsBored needs to see your keys."
            case .passthrough: "What happens to ⌘⇥ and friends in a remote session, practised on a sample one."
            case .trigger: "A key of your own that does one job, wherever you are."
            case .apps: "The apps that get macOS's shortcuts. Change them any time from the menu bar."
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "sparkles"
            case .access: "lock.shield"
            case .passthrough: "arrow.right.to.line"
            case .trigger: "keyboard"
            case .apps: "square.grid.2x2"
            }
        }
    }

    @ObservedObject var model: MacsBoredModel
    let onDone: () -> Void
    @State private var step: Step
    @State private var picked: Set<String> = []

    init(model: MacsBoredModel, startAt step: Step = .welcome, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _step = State(initialValue: step)
    }

    private var installed: [AppRef] {
        KnownPassthroughApps.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// The window's content size, as MacsPane's setup: room for a lesson's stage beside the sidebar.
    static let size = CGSize(width: 1000, height: 660)
    private static let sidebarWidth: CGFloat = 224
    private static let gutter: CGFloat = 36
    private static let footerHeight: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(SidebarMaterial())
            Divider().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).font(.system(size: 26, weight: .bold))
                    Text(step.subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .padding(.top, 36)
                .padding(.bottom, 18)
                .fixedSize(horizontal: false, vertical: true)
                Group {
                    switch step {
                    case .welcome: welcome
                    case .access: access
                    case .passthrough: PassthroughLesson()
                    case .trigger: TriggerLesson()
                    case .apps: apps
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(step)
                .transition(.opacity)
                footer
            }
            .padding(.horizontal, Self.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: Self.size.width, maxWidth: .infinity, minHeight: Self.size.height, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.18), value: step)
        .onAppear { picked = Set(installed.map(\.bundleID)) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                MacsBoredLogo(size: 40)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacsBored").font(.system(size: 15, weight: .semibold))
                    Text("First-time setup").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 28)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Step.allCases, id: \.self) { stepRow($0) }
            }
            .padding(.horizontal, 10)
            Spacer()
            Label {
                Text("You can change all of this later from the menu bar.").fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "menubar.arrow.up.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }

    /// A numbered step, ticked once passed.
    private func stepRow(_ item: Step) -> some View {
        let selected = item == step
        let passed = item.rawValue < step.rawValue
        return Button { step = item } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(selected || passed ? Color.accentColor : Color.primary.opacity(0.07))
                    if passed {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    } else {
                        Text("\(item.rawValue + 1)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(selected || passed ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                Text(item.sidebar)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(item.rawValue + 1), \(item.title)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Footer

    private var footer: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : Color.primary.opacity(item.rawValue < step.rawValue ? 0.35 : 0.15))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                }
                Spacer()
                if step == .apps {
                    Button("Start using MacsBored") {
                        model.addProfiles(for: installed.filter { picked.contains($0.bundleID) })
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { step = Step(rawValue: step.rawValue + 1) ?? .apps }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.large)
        .frame(height: Self.footerHeight)
        .overlay(alignment: .top) { Divider().padding(.horizontal, -Self.gutter) }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupCard {
                VStack(alignment: .leading, spacing: 16) {
                    explainer("arrow.right.to.line", "Pass shortcuts to a remote session",
                              "In Windows App, Citrix or a virtual machine, ⌘⇥, Spotlight and the rest go to the other computer, not your Mac.")
                    explainer("keyboard", "Give a key a job with a trigger",
                              "Remap keys, open an app, a link or a file, run a Shortcut, or pass just some keys to the app in front.")
                    explainer("menubar.rectangle", "Everything else is in the menu bar",
                              "Pausing, New, and Setup live under the MacsBored icon.")
                    explainer("doc.text", "Or set it all up from a file",
                              "Every setting is in one JSON file that MacsBored reloads the moment it changes, so you, a script or an AI agent can edit it.")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupCard {
                HStack(spacing: 13) {
                    IconTile(symbol: "keyboard", tint: .accentColor, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility").font(.callout.weight(.semibold))
                        Text("Lets MacsBored see keys before macOS acts on them, and tell when a window is full screen. It reads nothing else.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 14)
                    if model.isAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                    } else {
                        Button("Grant Access") { model.requestAccess() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Label(model.isAuthorized
                    ? "All set. Passthrough apps now get their shortcuts, and triggers work everywhere."
                    : "macOS opens System Settings at the Accessibility list. This step notices as soon as it's on. Until then, macOS keeps every shortcut.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(picked.count == 1 ? "1 app gets the shortcuts" : "\(picked.count) apps get the shortcuts")
                .font(.callout).foregroundStyle(.secondary)
            if installed.isEmpty {
                Text("No remote-desktop app is installed yet. Add one later with New in the menu bar.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(installed) { app in appCard(app, on: picked.contains(app.bundleID)) }
            }
            Spacer(minLength: 0)
            settingCard("power", "Open at login", "MacsBored starts with your Mac, so passthrough is always ready.") {
                Toggle("Open MacsBored at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
            }
            settingCard("capslock", "Caps Lock as Hyper", "Caps Lock holds ⌃⌥⇧⌘, a modifier no app uses, for triggers of your own.") {
                Toggle("Caps Lock as Hyper", isOn: Binding(get: { model.config.hyperKeyEnabled }, set: { model.setHyperKey($0) }))
            }
        }
        .padding(.bottom, 16)
    }

    /// A setting on a setup step, drawn the same as MacsPane's: its icon, name and line, and its switch.
    private func settingCard<Control: View>(_ symbol: String, _ title: String, _ detail: String,
                                            @ViewBuilder control: () -> Control) -> some View {
        SetupCard(padding: 10) {
            HStack(spacing: 10) {
                IconTile(symbol: symbol, tint: .secondary, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                control().toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
        }
    }

    private func appCard(_ app: AppRef, on: Bool) -> some View {
        Button {
            if on { picked.remove(app.bundleID) } else { picked.insert(app.bundleID) }
        } label: {
            VStack(spacing: 10) {
                if let icon = AppIcons.icon(bundleID: app.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                }
                HStack(spacing: 6) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                    Text(app.name).lineLimit(1)
                }
                .font(.callout)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func explainer(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, tint: .accentColor, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A rounded, faintly filled panel: the one card style every setup step uses, as in MacsPane.
struct SetupCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// The system sidebar material, so the step list reads like every other Mac setup window.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - The lessons' shared pieces

/// The line above a lesson's picture, with its buttons at its right.
private struct LessonIntro<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .controlSize(.small)
        .frame(height: 24)
    }
}

/// The top of a Mac screen: wallpaper and a menu bar naming the app in front.
private struct LessonDesktop<Content: View>: View {
    let frontApp: String
    var iconDimmed = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: scheme == .dark
                ? [Color(red: 0.19, green: 0.21, blue: 0.26), Color(red: 0.11, green: 0.12, blue: 0.15)]
                : [Color(red: 0.80, green: 0.85, blue: 0.91), Color(red: 0.70, green: 0.76, blue: 0.84)],
                startPoint: .top, endPoint: .bottom)
            content
            HStack(spacing: 12) {
                Text(frontApp).fontWeight(.semibold)
                Spacer()
                Image(systemName: "command").opacity(iconDimmed ? 0.35 : 1)
                Image(systemName: "wifi")
                Text("9:41")
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Color.white.opacity(scheme == .dark ? 0.06 : 0.28))
            .allowsHitTesting(false)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct LessonStep: View {
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }
}

/// A sample window: a title bar with traffic lights, lit while it's in front, over its content.
private struct SampleWindow<Content: View>: View {
    let title: String
    let front: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { color in
                    Circle().fill(front ? color : Color.gray.opacity(0.35)).frame(width: 9, height: 9)
                }
                Spacer()
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 39, height: 1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor))
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(front ? 0.25 : 0.12), radius: front ? 12 : 5, y: 4)
    }
}

/// Catches the lesson's keys while the setup window is in front. Keys macOS keeps for itself
/// (⌘⇥, ⌘Space) never arrive here, so each lesson also has buttons for them.
private struct KeyCatcher: ViewModifier {
    let handle: (KeyCombo) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let keys = KeyCombo(keyCode: event.keyCode, modifiers: FlagBits.modifiers(UInt64(event.modifierFlags.rawValue)))
                    return handle(keys) ? nil : event
                }
            }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

// MARK: - Try passthrough

/// A sample remote session: in it, ⌘⇥ and ⌘Space reach Windows; ⌃⌥⌘P pauses so macOS has them back;
/// clicking the desktop beside it puts Finder in front, where every shortcut is the Mac's.
private struct PassthroughLesson: View {
    enum Shown { case winSwitcher, winSearch, macSwitcher, spotlight }
    enum Event { case paused, resumed, pauseOnMac, left }

    @State private var remoteInFront = true
    @State private var paused = false
    @State private var shown: Shown?
    @State private var event: Event?
    @State private var sent = false
    @State private var triedPaused = false
    @State private var left = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LessonIntro(text: "Press a key in the sample session. Nothing on your Mac happens.") {
                Button("⌘⇥") { press(.tab) }
                Button("⌘Space") { press(.space) }
                Button("⌃⌥⌘P") { press(.pause) }
                Button("Start over") { reset() }.padding(.leading, 6)
            }
            LessonDesktop(frontApp: remoteInFront ? "Windows App" : "Finder", iconDimmed: paused && remoteInFront) {
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { remoteInFront = false; paused = false; shown = nil; event = .left; left = true }
                    SampleWindow(title: "Work PC · Windows App", front: remoteInFront) {
                        ZStack(alignment: .bottom) {
                            LinearGradient(colors: [Color(red: 0.16, green: 0.44, blue: 0.79), Color(red: 0.04, green: 0.24, blue: 0.48)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            HStack(spacing: 6) {
                                ForEach(0..<4) { index in
                                    RoundedRectangle(cornerRadius: 2).fill([Color.cyan, .green, .yellow, .blue][index].opacity(0.85))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: 22).background(Color.black.opacity(0.7))
                            if shown == .winSwitcher { windowsSwitcher.frame(maxHeight: .infinity) }
                            if shown == .winSearch { windowsSearch.padding(.bottom, 28) }
                        }
                    }
                    .frame(width: 460, height: 220)
                    .offset(y: 16)
                    .onTapGesture { remoteInFront = true; shown = nil; if event == .left { event = nil } }
                    if shown == .macSwitcher { macSwitcher }
                    if shown == .spotlight { spotlight.frame(maxHeight: .infinity, alignment: .top).padding(.top, 70) }
                    if paused && remoteInFront {
                        Label("Passthrough paused", systemImage: "pause.fill")
                            .font(.caption)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 30).padding(.trailing, 10)
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                LessonStep(title: "Press ⌘⇥ in the session", detail: "It reaches Windows as Alt+Tab, not your Mac's app switcher.", done: sent)
                LessonStep(title: "Pause with ⌃⌥⌘P, then press ⌘⇥", detail: "macOS gets its shortcuts back until you switch apps.", done: triedPaused)
                LessonStep(title: "Click the desktop beside it", detail: "Back on your Mac, every shortcut works as usual.", done: left)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.2), value: shown)
        .animation(.snappy(duration: 0.2), value: remoteInFront)
        .modifier(KeyCatcher { keys in
            if keys == MacsBoredConfig.defaultPauseKeys { press(.pause); return true }
            return false
        })
    }

    private enum Key { case tab, space, pause }

    private func press(_ key: Key) {
        if key == .pause {
            guard remoteInFront else { shown = nil; event = .pauseOnMac; return }
            paused.toggle()
            shown = nil
            event = paused ? .paused : .resumed
            return
        }
        let toSession = remoteInFront && !paused
        shown = toSession ? (key == .tab ? .winSwitcher : .winSearch) : (key == .tab ? .macSwitcher : .spotlight)
        event = nil
        if toSession { sent = true }
        if remoteInFront && paused { triedPaused = true }
    }

    private func reset() {
        remoteInFront = true; paused = false; shown = nil; event = nil; sent = false; triedPaused = false; left = false
    }

    private var status: String {
        switch (shown, event) {
        case (.winSwitcher?, _): return "Windows got ⌘⇥ as Alt+Tab. Your Mac's app switcher stayed shut."
        case (.winSearch?, _): return "⌘Space opened Windows search, not Spotlight."
        case (.macSwitcher?, _): return remoteInFront ? "Paused, so ⌘⇥ opened your Mac's app switcher. Press ⌃⌥⌘P again to resume."
                                                     : "On your Mac, ⌘⇥ opens the Mac's app switcher as usual."
        case (.spotlight?, _): return remoteInFront ? "Paused, so ⌘Space opened Spotlight on your Mac." : "On your Mac, ⌘Space opens Spotlight as usual."
        case (nil, .paused?): return "Paused. macOS has its shortcuts back until you switch apps. Press ⌘⇥ to see."
        case (nil, .resumed?): return "Resumed. Shortcuts go to the session again."
        case (nil, .pauseOnMac?): return "⌃⌥⌘P only does something while a passthrough app is in front."
        case (nil, .left?): return "Finder is in front, so every shortcut is your Mac's again. Click the session to go back."
        case (nil, nil): return remoteInFront ? "The sample session is in front, so its shortcuts go to Windows. Press ⌘⇥ to try."
                                              : "Finder is in front. Click the session to go back."
        }
    }

    private var windowsSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(["Excel", "Edge", "File Explorer"], id: \.self) { name in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(name == "Excel" ? 0.95 : 0.8))
                        .frame(width: 64, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white, lineWidth: name == "Excel" ? 2 : 0).padding(-3))
                    Text(name).font(.system(size: 10)).foregroundStyle(.white)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
    }

    private var windowsSearch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type here to search").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            Text("Windows search").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(8)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8)))
    }

    private var macSwitcher: some View {
        HStack(spacing: 12) {
            ForEach(["com.apple.finder", "com.microsoft.rdc.macos", "com.apple.Notes"], id: \.self) { id in
                Group {
                    if let icon = AppIcons.icon(bundleID: id) { Image(nsImage: icon).resizable() } else { RoundedRectangle(cornerRadius: 10).fill(.gray) }
                }
                .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var spotlight: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("Spotlight Search")
            Spacer()
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(width: 340, height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

// MARK: - Try a trigger

/// Three sample triggers: one opens Notes, one runs a Shortcut, one presses other keys.
private struct TriggerLesson: View {
    enum Sample: CaseIterable { case notes, focus, emoji }
    @State private var shown: Sample?
    @State private var done: Set<Sample> = []

    private static let keys: [Sample: KeyCombo] = [
        .notes: KeyCombo(text: "ctrl+opt+N")!, .focus: KeyCombo(text: "ctrl+opt+F")!, .emoji: KeyCombo(text: "ctrl+opt+E")!,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LessonIntro(text: "Press a sample trigger, here or on your keyboard.") {
                Button("⌃⌥N") { fire(.notes) }
                Button("⌃⌥F") { fire(.focus) }
                Button("⌃⌥E") { fire(.emoji) }
                Button("Start over") { shown = nil; done = [] }.padding(.leading, 6)
            }
            LessonDesktop(frontApp: shown == .notes ? "Notes" : "Finder") {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    SampleWindow(title: "Documents", front: shown != .notes) {
                        HStack(spacing: 0) {
                            Color.primary.opacity(0.05).frame(width: 80)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 10), count: 4), spacing: 10) {
                                ForEach(0..<4) { index in
                                    RoundedRectangle(cornerRadius: 4).fill(index < 2 ? Color.blue.opacity(0.35) : Color.gray.opacity(0.2))
                                        .frame(height: 30)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                    .frame(width: 300, height: 190)
                    .offset(x: 40, y: 48)
                    if shown == .notes {
                        SampleWindow(title: "Notes", front: true) {
                            HStack(spacing: 0) {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.yellow.opacity(0.6)).frame(height: 22)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)).frame(height: 22)
                                    Spacer()
                                }
                                .padding(8).frame(width: 110)
                                Text("Standup").font(.caption).padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .background(Color(nsColor: .textBackgroundColor))
                            }
                        }
                        .frame(width: 320, height: 190)
                        .offset(x: 300, y: 64)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    if shown == .focus {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [.pink, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Focus timer").font(.caption.weight(.semibold))
                                Text("Started · 25 minutes, Do Not Disturb on").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(width: 260, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 32).padding(.trailing, 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if shown == .emoji {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Search").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 2) {
                                ForEach(Array("😀😂😊😍👍🙏🎉🔥✅👀💡☕️🚀🙌😅❤️").map(String.init), id: \.self) { Text($0).font(.system(size: 16)) }
                            }
                        }
                        .padding(8)
                        .frame(width: 220)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        .offset(x: 150, y: 120)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                LessonStep(title: "⌃⌥N opens an app", detail: "Notes opens, or comes to the front if it's already open.", done: done.contains(.notes))
                LessonStep(title: "⌃⌥F runs a Shortcut", detail: "Anything Apple's Shortcuts app can do, from one key.", done: done.contains(.focus))
                LessonStep(title: "⌃⌥E remaps keys", detail: "It presses ⌃⌘Space for you, which opens the emoji picker.", done: done.contains(.emoji))
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: shown)
        .modifier(KeyCatcher { keys in
            guard let sample = Self.keys.first(where: { $0.value == keys })?.key else { return false }
            fire(sample)
            return true
        })
    }

    private func fire(_ sample: Sample) {
        shown = sample
        done.insert(sample)
    }

    private var status: String {
        if done.count == Sample.allCases.count { return "That's triggers. Make your own with New in the menu bar." }
        switch shown {
        case .notes?: return "Notes opened. If it was already open, the trigger brings it to the front."
        case .focus?: return "Your “Focus timer” Shortcut ran, from one key."
        case .emoji?: return "The trigger pressed ⌃⌘Space for you, so the emoji picker opened."
        case nil: return "Finder is in front. A trigger works in any app except a passthrough one."
        }
    }
}
#endif
