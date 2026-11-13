#if canImport(AppKit)
import AppKit
import MacsBoredCore

/// Live state for one grant card: whether the permission has landed, the deep link, and the escape
/// for a stale System Settings entry.
final class PermissionGrantModel: ObservableObject {
    @Published var granted: Bool
    let grant: PermissionGrant
    private let isGranted: () -> Bool
    private let prompt: (() -> Void)?
    private let poller = AccessibilityGrantPoller()
    private var onGranted: (() -> Void)?
    var onClose: (() -> Void)?

    init(grant: PermissionGrant, isGranted: @escaping () -> Bool, prompt: (() -> Void)? = nil) {
        self.grant = grant
        self.isGranted = isGranted
        self.prompt = prompt
        self.granted = isGranted()
    }

    func openSettings() {
        guard let url = grant.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func close() { onClose?() }

    /// Drop the entry macOS holds for this app, so a switch left on by an earlier copy of the app
    /// stops shadowing this one, then ask again and reopen the list.
    func startOver() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // Bounded, because this runs on the MAIN thread from a click: an unbounded `waitUntilExit`
        // on a wedged `tccutil` is a beachball with no way out. It normally answers in milliseconds.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", grant.tccService, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        if (try? process.run()) != nil, done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            NSLog("MacsBored: tccutil reset %@ for %@ did not finish; carrying on", grant.tccService, bundleID)
        }
        prompt?()
        openSettings()
    }

    /// Watch for the switch being flipped; `onGranted` fires once, after a beat on screen so the
    /// card can show that it noticed.
    func watch(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        guard !granted else { return }
        poller.start(isGranted: { [isGranted] in isGranted() }) { [weak self] in
            guard let self else { return }
            self.granted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.onGranted?() }
        }
    }

    func stop() { poller.stop() }
}

/// Polls Accessibility until it is granted, then calls back once on the main run loop and stops.
final class AccessibilityGrantPoller {
    private var timer: Timer?

    func start(isGranted: @escaping () -> Bool, onGrant: @escaping () -> Void) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard isGranted() else { return }
            timer.invalidate()
            self.timer = nil
            onGrant()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
