#if canImport(AppKit)
import AppKit
import SwiftUI
import ApplicationServices
import MacsBoredCore

/// The one way MacsBored asks for a system permission, as MacsPane does: it opens the right list in System Settings and
/// hangs a small dropdown under that window holding the app's icon, so adding the app is one drag
/// into the list above. The dropdown shows only while the Settings window is in front, follows it as
/// it moves, and goes away by itself once access is on or Settings is closed. Every needs-access
/// surface calls this.
public final class PermissionGrantPresenter: NSObject {
    public static let shared = PermissionGrantPresenter()

    private var panel: PermissionDropdownPanel?
    private var model: PermissionGrantModel?
    private var follow: Timer?
    /// Whether the Settings window has been seen since the dropdown opened, so its closing can close
    /// the dropdown too (rather than the dropdown closing before Settings has had time to open).
    private var sawSettings = false

    private static let settingsBundleID = "com.apple.systempreferences"

    /// Show the dropdown for `grant`. `isGranted` is polled so it can confirm and close itself;
    /// `prompt` is the app's own one-shot system prompt, which also puts the app in the list.
    public func present(_ grant: PermissionGrant, isGranted: @escaping () -> Bool,
                        prompt: (() -> Void)? = nil, openPane: Bool = true,
                        onGranted: (() -> Void)? = nil) {
        guard !isGranted() else { onGranted?(); return }
        close()
        prompt?()
        let model = PermissionGrantModel(grant: grant, isGranted: isGranted, prompt: prompt)
        model.onClose = { [weak self] in self?.close() }
        self.model = model
        let view = PermissionDropdownView(grant: grant, appName: Self.appName, appURL: Bundle.main.bundleURL,
                                          model: model)
        let hosting = NSHostingView(rootView: view)
        let panel = PermissionDropdownPanel(size: hosting.fittingSize)
        panel.contentView = hosting
        self.panel = panel
        sawSettings = false
        if openPane { model.openSettings() }
        place()
        follow = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.place() }
        model.watch { [weak self] in
            onGranted?()
            self?.close()
        }
    }

    public func close() {
        follow?.invalidate()
        follow = nil
        model?.stop()
        model = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Dock under the Settings window, wherever it is now, and show only while that window is the one in
    /// front: switch to another app and the dropdown steps aside, come back and it is there again. Close
    /// once Settings has come and gone.
    private func place() {
        guard let panel else { return }
        let settingsApp = NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).first
        let settings = settingsApp.flatMap(settingsWindowFrame)
        if settings != nil {
            sawSettings = true
        } else if sawSettings, model?.granted == false {
            close()
            return
        }
        guard let settings, settingsApp?.isActive == true || model?.granted == true else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = PermissionDropdownPlacement.frame(size: panel.frame.size, settingsWindow: settings,
                                                      visibleFrame: visible)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// The System Settings window's frame in AppKit coordinates, or nil while it isn't on screen.
    private func settingsWindowFrame(_ app: NSRunningApplication) -> CGRect? {
        guard let window = PermissionDropdownPlacement.settingsWindow(in: Self.windowRoster(),
                                                                      ownerPid: app.processIdentifier)
        else { return nil }
        return window.frame.flipped(primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MacsBored"
    }

    /// The window server's roster, front to back. `CGWindowListCopyWindowInfo` needs no Screen
    /// Recording for frames, owners and layers.
    private static func windowRoster() -> [ProcessWindowInfo] {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? Int,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  let bounds = dict[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return ProcessWindowInfo(id: UInt32(id), ownerPid: Int32(pid), frame: frame,
                                     isOnScreen: dict[kCGWindowIsOnscreen as String] as? Bool ?? false, layer: layer)
        }
    }
}

extension PermissionGrantPresenter {
    /// Accessibility, the list MacsBored is switched on in. The system prompt is shown first (it is
    /// the one click that can finish the job), then the dropdown walks the manual route.
    public func requestAccessibility(onGranted: (() -> Void)? = nil) {
        present(.accessibility, isGranted: { AXIsProcessTrusted() },
                prompt: { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) },
                onGranted: onGranted)
    }
}

/// The dropdown's window: borderless and see-through around its rounded shape, floating above System
/// Settings, and never taking focus from it, so the list you drop into stays the active window.
final class PermissionDropdownPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
}
#endif
