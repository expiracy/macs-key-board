#if canImport(AppKit)
import AppKit
import Combine
import MacsKeyBoredCore

/// The app's state and everything that changes it. Several times a second it reads what is in front
/// (`ContextReader`), works out the passthrough plan, switches macOS's system shortcuts to match and
/// hands the keyboard tap its new setup. Every change to the config is saved straight away.
@MainActor
final class MacsKeyBoredModel: ObservableObject {
    @Published private(set) var config: MacsKeyBoredConfig
    @Published private(set) var context = AppContext()
    @Published private(set) var plan = PassthroughPlan.inactive
    /// Paused for this app: passthrough resumes once another app comes to the front.
    @Published private(set) var pausedFor: String?
    @Published private(set) var isAuthorized = Accessibility.isTrusted
    @Published private(set) var tapRunning = false
    @Published private(set) var hyperBlocked = false
    /// While a shortcut is being recorded, the tap lets every key through to the recorder.
    var isRecording = false { didSet { pushSetup() } }

    var onEditProfile: (PassthroughProfile, Bool) -> Void = { _, _ in }
    var onEditTrigger: (Trigger, Bool) -> Void = { _, _ in }
    var onShowSetup: () -> Void = {}
    var onPlanChange: (PassthroughPlan, Bool) -> Void = { _, _ in }

    private let store: MacsKeyBoredConfigStore
    private let reader = ContextReader()
    private let hotKeys = SystemHotKeySwitch()
    private let tap = KeyboardTap()
    private let keepAwake = KeepAwake()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(store: MacsKeyBoredConfigStore) {
        self.store = store
        self.config = store.config
    }

    var hotKeySwitchAvailable: Bool { SymbolicHotKeys.isAvailable }
    /// How many system shortcuts are switched off right now (ones already off in System Settings aren't counted).
    var systemShortcutsOff: Int { hotKeys.disabledCount }
    var isPaused: Bool { pausedFor != nil }
    var keepAwakeOn: Bool { keepAwake.isOn }

    // MARK: - Running

    func start() {
        hotKeys.restoreLeftovers()
        tap.onDecision = { [weak self] decision in self?.handle(decision) }
        keepAwake.set(config.keepAwake)
        applyHyper()
        startTapIfAllowed()
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

    /// Everything back as macOS had it: system shortcuts, Caps Lock, sleep.
    func stop() {
        timer?.invalidate()
        hotKeys.restoreAll()
        HyperKeyMapping.set(false)
        keepAwake.set(false)
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
            switch trigger.action {
            case .togglePause: togglePause()
            case .toggleKeepAwake: setKeepAwake(!keepAwake.isOn)
            default: ActionRunner.run(trigger.action)
            }
        default:
            break
        }
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

    func setKeepAwake(_ on: Bool) {
        keepAwake.set(on)
        update { $0.keepAwake = on }
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

    // MARK: - Profiles

    func newProfile(for app: AppRef) {
        onEditProfile(PassthroughProfile(name: app.name, apps: [app]), true)
    }

    /// Setup's shortcut: a profile with the defaults for each app picked, straight away.
    func addProfiles(for apps: [AppRef]) {
        update { config in
            for app in apps where !config.profiles.contains(where: { $0.covers(bundleID: app.bundleID) }) {
                config.profiles.append(PassthroughProfile(name: app.name, apps: [app]))
            }
        }
    }

    func editProfile(_ id: UUID) {
        guard let profile = config.profiles.first(where: { $0.id == id }) else { return }
        onEditProfile(profile, false)
    }

    func saveProfile(_ profile: PassthroughProfile) {
        update { config in
            if let index = config.profiles.firstIndex(where: { $0.id == profile.id }) {
                config.profiles[index] = profile
            } else {
                config.profiles.append(profile)
            }
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

    // MARK: - Triggers

    func newTrigger(_ action: TriggerAction.Kind) {
        onEditTrigger(Trigger(name: action.title, shortcut: nil, action: action.blank), true)
    }

    func editTrigger(_ id: UUID) {
        guard let trigger = config.triggers.first(where: { $0.id == id }) else { return }
        onEditTrigger(trigger, false)
    }

    /// Saves the trigger; a shortcut another trigger had is taken from it, as MacsPane does.
    func saveTrigger(_ trigger: Trigger) {
        update { config in
            if let keys = trigger.shortcut {
                for index in config.triggers.indices where config.triggers[index].id != trigger.id
                    && config.triggers[index].shortcut == keys && config.triggers[index].apps == trigger.apps {
                    config.triggers[index].shortcut = nil
                }
            }
            if let index = config.triggers.firstIndex(where: { $0.id == trigger.id }) {
                config.triggers[index] = trigger
            } else {
                config.triggers.append(trigger)
            }
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

    private func update(_ change: (inout MacsKeyBoredConfig) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        config = next
        try? store.save(next)
        recompute()
        onPlanChange(plan, config.passthroughEnabled)
    }
}
#endif
