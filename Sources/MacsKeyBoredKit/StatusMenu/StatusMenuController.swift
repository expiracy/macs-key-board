#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI

/// Hangs `StatusMenuView` under the menu-bar icon in its own borderless panel, a bubble whose nub
/// points at the icon, and gives it a menu's
/// manners: a click on the icon opens and closes it, a click anywhere else or `esc` closes it, and
/// ⌘Q works while it is open. The panel takes the keyboard without activating the app, so the
/// app you were in stays in front.
final class StatusMenuController: NSObject, NSWindowDelegate {
    private let model: StatusMenuModel
    private weak var button: NSStatusBarButton?
    private var panel: StatusMenuPanel?
    private var monitors: [Any] = []
    private var resize: AnyCancellable?
    private var tick: Timer?

    /// The gap between the menu bar and the nub's tip, and the least distance from a screen edge.
    private static let gap: CGFloat = 3
    private static let screenMargin: CGFloat = 8

    init(button: NSStatusBarButton, model: StatusMenuModel) {
        self.model = model
        self.button = button
        super.init()
        button.target = self
        button.action = #selector(toggle)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        model.onClose = { [weak self] in self?.close() }
    }

    @objc private func toggle() {
        if panel == nil { open() } else { close() }
    }

    /// Open the dropdown, as a click on the icon does.
    func show() {
        if panel == nil { open() }
    }

    private func open() {
        guard let button, let buttonWindow = button.window else { return }
        model.refresh()
        // The view draws its own bubble; the panel around it is clear, and its shadow follows the bubble.
        let host = NSHostingView(rootView: StatusMenuView(model: model))
        let panel = StatusMenuPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel
        place(panel, under: buttonWindow.frame, on: buttonWindow.screen)
        panel.makeKeyAndOrderFront(nil)
        // The button drops its highlight on mouse-up; put it back once that has happened.
        DispatchQueue.main.async { [weak self] in
            if self?.panel != nil { button.highlight(true) }
        }
        installMonitors(ignoring: buttonWindow)
        // What is in front changes the Now card: refit, holding the top edge under the icon.
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.model.refresh() }
        resize = model.$content.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, let panel = self.panel, let window = self.button?.window else { return }
            self.place(panel, under: window.frame, on: window.screen)
        }
    }

    func close() {
        guard let panel else { return }
        model.openSubmenu = nil
        self.panel = nil
        resize = nil
        tick?.invalidate()
        tick = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.delegate = nil
        panel.orderOut(nil)
        button?.highlight(false)
    }

    /// Centred under the icon, pulled in from a screen edge when the icon sits close to it; the nub
    /// still points at the icon.
    private func place(_ panel: NSPanel, under anchor: NSRect, on screen: NSScreen?) {
        guard let host = panel.contentView else { return }
        let size = host.fittingSize
        var x = anchor.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(x, visible.maxX - size.width - Self.screenMargin)
            x = max(x, visible.minX + Self.screenMargin)
        }
        if model.nubX != anchor.midX - x { model.nubX = anchor.midX - x }
        panel.setFrame(NSRect(x: x, y: anchor.minY - Self.gap - size.height, width: size.width, height: size.height),
                       display: true)
        panel.invalidateShadow()
    }

    private func installMonitors(ignoring buttonWindow: NSWindow) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Another app's window, the desktop, another menu-bar item.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
        // One of our own windows. The icon's own click is left to `toggle`.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            if let self, event.window !== self.panel, event.window !== buttonWindow { self.close() }
            return event
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.panel != nil else { return event }
            return self.handle(event) ? nil : event
        }) { monitors.append(keys) }
    }

    private func handle(_ key: NSEvent) -> Bool {
        let command = key.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        switch (key.keyCode, key.charactersIgnoringModifiers) {
        case (53, _) where model.openSubmenu != nil:
            model.openSubmenu = nil
        case (53, _):
            close()
        case (_, "q"?) where command:
            model.onQuit()
        default:
            return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Borderless panels refuse the keyboard by default; this one needs `esc` and ⌘Q.
private final class StatusMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
#endif
