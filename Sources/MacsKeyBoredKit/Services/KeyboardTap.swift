#if canImport(AppKit)
import AppKit
import MacsKeyBoredCore

/// The keyboard event tap: every key-down, key-up and modifier change passes through `KeyRouter`
/// before the system acts on it. It runs on its own thread with its own run loop, so a slow main
/// thread (an app slow to answer Accessibility) never delays a key; the main thread only hands it a
/// fresh `KeyRouter.Setup` when something changes, and hears back about triggers and the pause.
///
/// It sits at the HID level, ahead of other apps' global shortcuts, and needs Accessibility.
final class KeyboardTap {
    /// Marks events this app posts itself, so the tap lets them by.
    static let ownEventTag: Int64 = 0x4D4B_4244   // "MKBD"

    /// Runs on the main thread when a decision needs the app (a trigger, the pause).
    var onDecision: (KeyDecision) -> Void = { _ in }

    private let lock = NSLock()
    private var _setup = KeyRouter.Setup(plan: .inactive, triggers: [], context: AppContext(),
                                         pauseKeys: nil, hyperKeyEnabled: false)
    private var router = KeyRouter()   // tap thread only
    private var port: CFMachPort?
    private var thread: Thread?
    private(set) var isRunning = false

    var setup: KeyRouter.Setup {
        get { lock.lock(); defer { lock.unlock() }; return _setup }
        set { lock.lock(); _setup = newValue; lock.unlock() }
    }

    /// Starts the tap; false when macOS refuses it (no Accessibility yet).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: keyboardTapCallback,
                                           userInfo: me)
                ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                     eventsOfInterest: CGEventMask(mask), callback: keyboardTapCallback,
                                     userInfo: me)
        else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "MacsKeyBored keyboard tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        isRunning = true
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a tap off when it is slow once; put it straight back.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventTag {
            return Unmanaged.passUnretained(event)
        }
        let phase: KeyEvent.Phase = type == .keyDown ? .down : type == .keyUp ? .up : .flagsChanged
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let key = KeyEvent(phase: phase, keyCode: keyCode, modifiers: FlagBits.modifiers(event.flags.rawValue),
                           isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        let setup = self.setup
        let decision = router.route(key, setup)
        let swapped = setup.plan.isActive && setup.plan.modifierLayout == .swapCommandControl

        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case let .modify(code, modifiers):
            Self.rewrite(event, keyCode: code, modifiers: modifiers, swapped: swapped)
            return Unmanaged.passUnretained(event)
        case let .forward(pid, code, modifiers):
            guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
            Self.rewrite(copy, keyCode: code, modifiers: modifiers, swapped: swapped)
            copy.setIntegerValueField(.eventSourceUserData, value: Self.ownEventTag)
            copy.postToPid(pid_t(pid))
            return nil
        case .runTrigger, .togglePause:
            DispatchQueue.main.async { [weak self] in self?.onDecision(decision) }
            return nil
        case .swallow:
            return nil
        }
    }

    private static func rewrite(_ event: CGEvent, keyCode: UInt16, modifiers: KeyCombo.Modifiers, swapped: Bool) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.flags = CGEventFlags(rawValue: FlagBits.rewrite(event.flags.rawValue, to: modifiers,
                                                              swappedCommandControl: swapped))
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyboardTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
#endif
