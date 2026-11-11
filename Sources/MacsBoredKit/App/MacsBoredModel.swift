#if canImport(AppKit)
import AppKit
import Combine
import MacsBoredCore

/// The app's state and everything that changes it. Several times a second it reads what is in front
/// (`ContextReader`), works out the passthrough plan, switches macOS's system shortcuts to match and
/// hands the keyboard tap its new setup. The settings live in `config.json`: every change is saved
/// straight away, and an edit made to the file by hand, a script or an agent is picked up as soon as
/// it's saved. A file with a mistake leaves the last good settings running until it's fixed.
@MainActor
final class MacsBoredModel: ObservableObject {
    @Published private(set) var config: MacsBoredConfig
    /// What's wrong with `config.json` as it is on disk (errors and warnings).
    @Published private(set) var fileIssues: [ConfigFile.Issue]
    @Published private(set) var context = AppContext()
    @Published private(set) var plan = PassthroughPlan.inactive
    /// Paused for this app: passthrough resumes once another app comes to the front.
    @Published private(set) var pausedFor: String?
    @Published private(set) var isAuthorized = Accessibility.isTrusted
    @Published private(set) var tapRunning = false
    @Published private(set) var hyperBlocked = false
    /// While keys are being recorded, the tap lets every key through to the recorder.
    var isRecording = false { didSet { pushSetup() } }

    var onEdit: (EntryDraft) -> Void = { _ in }
    var onShowSetup: () -> Void = {}
    var onPlanChange: (PassthroughPlan, Bool) -> Void = { _, _ in }

    private let store: MacsBoredConfigStore
    private let reader = ContextReader()
    private let hotKeys = SystemHotKeySwitch()
    private let tap = KeyboardTap()
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var observers: [NSObjectProtocol] = []

    init(store: MacsBoredConfigStore) {
        self.store = store
        self.config = store.config
        self.fileIssues = store.issues
    }

    var configURL: URL { store.url }
    var fileErrors: [ConfigFile.Issue] { fileIssues.filter { !$0.isWarning } }
    var hotKeySwitchAvailable: Bool { SymbolicHotKeys.isAvailable }
    /// How many system shortcuts are switched off right now (ones already off in System Settings aren't counted).
    var systemShortcutsOff: Int { hotKeys.disabledCount }
    var isPaused: Bool { pausedFor != nil }
    var openAtLogin: Bool { LoginItem.isEnabled }

    // MARK: - Running

    func start() {
        hotKeys.restoreLeftovers()
        tap.onDecision = { [weak self] decision in self?.handle(decision) }
        applyHyper()
        applyLogin()
        startTapIfAllowed()
        watchFile()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    /// Everything back as macOS had it: system shortcuts and Caps Lock.
    func stop() {
        timer?.invalidate()
        watcher?.cancel()
        hotKeys.restoreAll()
        HyperKeyMapping.set(false)
    }

    private func startTapIfAllowed() {
        isAuthorized = Accessibility.isTrusted
        if isAuthorized, !tap.isRunning { tapRunning = tap.start() }
    }

    private func tick() {
        if !tap.isRunning { startTapIfAllowed() }
        let now = reader.read()
        if let paused = pausedFor, now.bundleID != paused { pausedFor = nil }
        if now != context { context = now }
        recompute()
    }

    private func recompute() {
        let profiles = config.passthroughEnabled ? config.profiles : []
        let next = PassthroughPlanner.plan(profiles: profiles, context: context, paused: isPaused || isRecording)
        hotKeys.move(to: next.disabledHotKeys)
        if next != plan {
            plan = next
            onPlanChange(next, config.passthroughEnabled)
        }
        pushSetup()
    }

    private func pushSetup() {
        tap.setup = KeyRouter.Setup(plan: isRecording ? .inactive : plan,
                                    triggers: isRecording ? [] : config.triggers,
                                    context: context,
                                    pauseKeys: isRecording ? nil : config.pauseKeys,
                                    hyperKeyEnabled: config.hyperKeyEnabled && !hyperBlocked)
    }

    private func handle(_ decision: KeyDecision) {
        switch decision {
        case .togglePause:
            togglePause()
        case let .runTrigger(id):
            guard let trigger = config.triggers.first(where: { $0.id == id }) else { return }
            ActionRunner.run(trigger.action)
        default:
            break
        }
    }

    // MARK: - The file

    /// The folder is watched rather than the file: saving replaces the file, which would end a watch on it.
    private func watchFile() {
        let folder = store.url.deletingLastPathComponent()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reloadFromDisk() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Takes in an edit made outside the app.
    func reloadFromDisk() {
        guard store.reload() else { return }
        fileIssues = store.issues
        guard store.config != config else { return }
        config = store.config
        applyHyper()
        applyLogin()
        recompute()
        onPlanChange(plan, config.passthroughEnabled)
    }

    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    func openConfigFile() {
        NSWorkspace.shared.open(store.url)
    }

    // MARK: - Switches

    func togglePause() {
        if pausedFor != nil {
            pausedFor = nil
        } else if plan.isActive {
            pausedFor = context.bundleID
        }
        recompute()
        onPlanChange(plan, config.passthroughEnabled)
    }

    func setPassthroughEnabled(_ on: Bool) {
        update { $0.passthroughEnabled = on }
    }

    func setOpenAtLogin(_ on: Bool) {
        update { $0.openAtLogin = on }
        applyLogin()
    }

    private func applyLogin() {
        if let wanted = config.openAtLogin, wanted != LoginItem.isEnabled { LoginItem.setEnabled(wanted) }
    }

    func setHyperKey(_ on: Bool) {
        update { $0.hyperKeyEnabled = on }
        applyHyper()
        pushSetup()
    }

    private func applyHyper() {
        let outcome = HyperKeyMapping.set(config.hyperKeyEnabled)
        hyperBlocked = outcome == .blockedByOtherMapping
    }

    func setPauseKeys(_ keys: KeyCombo?) {
        update { $0.pauseKeys = keys }
    }

    func requestAccess() {
        Accessibility.request()
    }

    func completeSetup() {
        update { $0.setupCompleted = true }
    }

    // MARK: - Entries

    /// The editor on a new entry; its tabs say what it becomes.
    func newEntry() {
        onEdit(EntryDraft())
    }

    /// The editor on the passthrough tab with this app in it, as the Now card's "Pass through…" offers.
    func newProfile(for app: AppRef) {
        var draft = EntryDraft()
        draft.tab = .passthrough
        draft.apps = [app]
        onEdit(draft)
    }

    /// Setup's shortcut: a passthrough entry with the defaults for each app picked, straight away.
    func addProfiles(for apps: [AppRef]) {
        update { config in
            for app in apps where !config.profiles.contains(where: { $0.covers(bundleID: app.bundleID) }) {
                config.profiles.append(PassthroughProfile(name: app.name, apps: [app]))
            }
        }
    }

    func editProfile(_ id: UUID) {
        guard let profile = config.profiles.first(where: { $0.id == id }) else { return }
        onEdit(EntryDraft(profile: profile))
    }

    func editTrigger(_ id: UUID) {
        guard let trigger = config.triggers.first(where: { $0.id == id }) else { return }
        onEdit(EntryDraft(trigger: trigger))
    }

    /// The trigger another one would take its keys from, for the editor's warning.
    func trigger(using keys: KeyCombo, apps: [AppRef], except id: UUID?) -> Trigger? {
        config.triggers.first { $0.id != id && $0.keys.contains(keys) && $0.apps == apps }
    }

    /// Saves what the editor made. It replaces the entry it was opened on, in its place when it is
    /// still the same kind, so switching a passthrough app to a trigger moves it between the lists.
    /// Keys another trigger had in the same place are taken from it.
    func save(_ result: EntryDraft.Result, replacing origin: EntryDraft.Origin) {
        update { config in
            var triggerSlot: Int?
            var profileSlot: Int?
            switch origin {
            case .new: break
            case let .trigger(id):
                triggerSlot = config.triggers.firstIndex { $0.id == id }
                config.triggers.removeAll { $0.id == id }
            case let .profile(id):
                profileSlot = config.profiles.firstIndex { $0.id == id }
                config.profiles.removeAll { $0.id == id }
            }
            switch result {
            case let .trigger(trigger):
                for index in config.triggers.indices where config.triggers[index].apps == trigger.apps {
                    config.triggers[index].keys.removeAll { trigger.keys.contains($0) }
                }
                config.triggers.insert(trigger, at: min(triggerSlot ?? config.triggers.count, config.triggers.count))
            case let .profile(profile):
                config.profiles.insert(profile, at: min(profileSlot ?? config.profiles.count, config.profiles.count))
            }
        }
    }

    func delete(_ origin: EntryDraft.Origin) {
        switch origin {
        case .new: break
        case let .trigger(id): deleteTrigger(id)
        case let .profile(id): deleteProfile(id)
        }
    }

    func deleteProfile(_ id: UUID) {
        update { $0.profiles.removeAll { $0.id == id } }
    }

    func toggleProfile(_ id: UUID) {
        update { config in
            guard let index = config.profiles.firstIndex(where: { $0.id == id }) else { return }
            config.profiles[index].isEnabled.toggle()
        }
    }

    func deleteTrigger(_ id: UUID) {
        update { $0.triggers.removeAll { $0.id == id } }
    }

    func toggleTrigger(_ id: UUID) {
        update { config in
            guard let index = config.triggers.firstIndex(where: { $0.id == id }) else { return }
            config.triggers[index].isEnabled.toggle()
        }
    }

    // MARK: -

    /// A change from the app, made to the settings as they are on disk now. While the file has a
    /// mistake nothing is written over it; the menu says so instead.
    private func update(_ change: (inout MacsBoredConfig) -> Void) {
        reloadFromDisk()
        var next = config
        change(&next)
        guard next != config else { return }
        do {
            try store.save(next)
        } catch {
            fileIssues = store.issues
            NSSound.beep()
            return
        }
        config = store.config
        fileIssues = store.issues
        recompute()
        onPlanChange(plan, config.passthroughEnabled)
    }
}
#endif
