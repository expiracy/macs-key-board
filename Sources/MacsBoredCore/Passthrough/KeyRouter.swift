import Foundation

/// One keyboard event as the event tap sees it.
public struct KeyEvent: Equatable, Sendable {
    public enum Phase: Sendable { case down, up, flagsChanged }

    public var phase: Phase
    public var keyCode: UInt16
    public var modifiers: KeyCombo.Modifiers
    public var isRepeat: Bool

    public init(phase: Phase, keyCode: UInt16, modifiers: KeyCombo.Modifiers, isRepeat: Bool = false) {
        self.phase = phase
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

/// What the tap does with an event.
public enum KeyDecision: Equatable, Sendable {
    /// Let it go on unchanged.
    case pass
    /// Let it go on with another key code or modifiers.
    case modify(keyCode: UInt16, modifiers: KeyCombo.Modifiers)
    /// Take it from the system and post it to this app alone.
    case forward(pid: Int32, keyCode: UInt16, modifiers: KeyCombo.Modifiers)
    /// Take it and run the trigger.
    case runTrigger(UUID)
    /// Take it and pause or resume passthrough.
    case togglePause
    /// Take it and do nothing.
    case swallow
}

/// Decides, event by event, what the keyboard does: the Hyper key, the pause keys, your triggers,
/// then passthrough. It remembers only what spans events: whether Hyper is held, and where each
/// held key's key-up belongs.
public struct KeyRouter: Sendable {
    public struct Setup: Sendable {
        public var plan: PassthroughPlan
        public var triggers: [Trigger]
        public var context: AppContext
        public var pauseKeys: KeyCombo?
        public var hyperKeyEnabled: Bool

        public init(plan: PassthroughPlan, triggers: [Trigger], context: AppContext, pauseKeys: KeyCombo?,
                    hyperKeyEnabled: Bool) {
            self.plan = plan
            self.triggers = triggers
            self.context = context
            self.pauseKeys = pauseKeys
            self.hyperKeyEnabled = hyperKeyEnabled
        }
    }

    /// Caps Lock (remapped to F18) is down, so every key gets ⌃⌥⇧⌘.
    private var hyperHeld = false
    /// Keys whose key-down went to a passthrough app: their key-up goes there too, even if another
    /// app has come to the front meanwhile, so the session never sees a key stuck down.
    private var forwardedUps: [UInt16: (pid: Int32, layout: ModifierLayout)] = [:]
    /// Keys whose key-down ran a trigger or the pause: their key-up (and repeats) go nowhere.
    private var takenUps: Set<UInt16> = []

    public init() {}

    public mutating func route(_ event: KeyEvent, _ setup: Setup) -> KeyDecision {
        if !setup.hyperKeyEnabled { hyperHeld = false }
        if setup.hyperKeyEnabled, event.keyCode == KeyCombo.Code.f18, event.phase != .flagsChanged {
            hyperHeld = event.phase == .down
            return .swallow
        }
        let held = hyperHeld && event.phase != .flagsChanged ? event.modifiers.union(.hyper) : event.modifiers

        switch event.phase {
        case .up:
            if let owner = forwardedUps.removeValue(forKey: event.keyCode) {
                let (code, modifiers) = Self.remap(event.keyCode, held, phase: .up, layout: owner.layout)
                return .forward(pid: owner.pid, keyCode: code, modifiers: modifiers)
            }
            if takenUps.remove(event.keyCode) != nil { return .swallow }
        case .down:
            let keys = KeyCombo(keyCode: event.keyCode, modifiers: held)
            if keys == setup.pauseKeys {
                takenUps.insert(event.keyCode)
                return event.isRepeat ? .swallow : .togglePause
            }
            if let trigger = setup.triggers.first(where: {
                $0.fires(on: keys, context: setup.context, passthroughActive: setup.plan.isActive)
            }) {
                if trigger.action == .passThrough {
                    // Its own keys, straight to the app in front, ahead of macOS and other apps.
                    guard let pid = setup.context.processID else { return .pass }
                    forwardedUps[event.keyCode] = (pid, .asIs)
                    return .forward(pid: pid, keyCode: event.keyCode, modifiers: held)
                }
                takenUps.insert(event.keyCode)
                return event.isRepeat ? .swallow : .runTrigger(trigger.id)
            }
        case .flagsChanged:
            break
        }
        return passthrough(event, modifiers: held, plan: setup.plan)
    }

    /// The front app's passthrough: its modifier layout, and, when it captures every key, the key
    /// itself posted straight to it. Modifier keys alone always travel the ordinary way, so the
    /// system's idea of what is held stays right.
    private mutating func passthrough(_ event: KeyEvent, modifiers: KeyCombo.Modifiers,
                                      plan: PassthroughPlan) -> KeyDecision {
        let layout = plan.isActive ? plan.modifierLayout : .asIs
        let (code, mapped) = Self.remap(event.keyCode, modifiers, phase: event.phase, layout: layout)
        if plan.isActive, plan.captureAllKeys, event.phase != .flagsChanged, let pid = plan.processID {
            if event.phase == .down { forwardedUps[event.keyCode] = (pid, layout) }
            return .forward(pid: pid, keyCode: code, modifiers: mapped)
        }
        return code == event.keyCode && mapped == event.modifiers ? .pass : .modify(keyCode: code, modifiers: mapped)
    }

    /// The key and modifiers as `layout` has them reach the app.
    static func remap(_ keyCode: UInt16, _ modifiers: KeyCombo.Modifiers, phase: KeyEvent.Phase,
                      layout: ModifierLayout) -> (UInt16, KeyCombo.Modifiers) {
        switch layout {
        case .asIs:
            return (keyCode, modifiers)
        case .swapCommandControl:
            var swapped = modifiers.subtracting([.command, .control])
            if modifiers.contains(.command) { swapped.insert(.control) }
            if modifiers.contains(.control) { swapped.insert(.command) }
            guard phase == .flagsChanged else { return (keyCode, swapped) }
            let keys: [UInt16: UInt16] = [
                KeyCombo.Code.leftCommand: KeyCombo.Code.leftControl, KeyCombo.Code.leftControl: KeyCombo.Code.leftCommand,
                KeyCombo.Code.rightCommand: KeyCombo.Code.rightControl, KeyCombo.Code.rightControl: KeyCombo.Code.rightCommand,
            ]
            return (keys[keyCode] ?? keyCode, swapped)
        }
    }
}
