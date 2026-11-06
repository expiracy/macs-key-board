#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsKeyBoredCore

/// MacsKeyBored: a menu-bar app that hands macOS's own shortcuts to the apps that should have them
/// (Windows App, Citrix Viewer, a VM) and runs your own triggers everywhere else. One boot path for
/// `swift run macskeybored` and the bundled app.
///
///   --smoke-test      Boot, then quit after ~1.5 s: a launch check.
///   --export-icon <dir>   Write the icon's PNGs (for scripts/make_icon.sh) and quit.
///   --open-menu       Open the dropdown once launched.
///   --open-editor profile|trigger   Open an editor on a new one (Windows App; Type text).
public enum MacsKeyBoredApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        if let index = arguments.firstIndex(of: "--export-icon"), index + 1 < arguments.count {
            MainActor.assumeIsolated { exportIcon(to: URL(fileURLWithPath: arguments[index + 1])) }
            return
        }
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { MacsKeyBoredAppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            MainActor.assumeIsolated {
                if arguments.contains("--open-menu") { delegate.openMenu() }
                if let index = arguments.firstIndex(of: "--open-editor"), index + 1 < arguments.count {
                    delegate.openEditor(arguments[index + 1])
                }
            }
        }
        if arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("MacsKeyBored: smoke-test OK: launched cleanly, shutting down")
                NSApp.terminate(nil)
            }
        }
        app.run()
    }

    @MainActor private static func exportIcon(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            if let data = MacsKeyBoredLogo.pngData(size: CGFloat(size), face: .light) {
                try? data.write(to: directory.appendingPathComponent("icon_\(size).png"))
            }
        }
        // The layers of App/AppIcon.icon, one per appearance.
        for (face, name) in [(ColorScheme.light, "marks-light"), (.dark, "marks-dark")] {
            if let data = MacsKeyBoredLogo.pngData(size: 1024, face: face, marksOnly: true) {
                try? data.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }
}

/// The composition root: the config file, the model, the menu-bar icon and its dropdown, the editors
/// and setup. Quitting, or a TERM or INT signal, puts every macOS shortcut back first.
@MainActor
final class MacsKeyBoredAppDelegate: NSObject, NSApplicationDelegate {
    private var model: MacsKeyBoredModel?
    private var statusItem: NSStatusItem?
    private var menu: StatusMenuController?
    private let editor = EditorWindowController()
    private let setup = EditorWindowController()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let url = (try? MacsKeyBoredPaths.configURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("macskeybored-config.json")
        let model = MacsKeyBoredModel(store: MacsKeyBoredConfigStore(url: url))
        self.model = model
        model.onEditProfile = { [weak self, weak model] profile, isNew in
            guard let self, let model else { return }
            self.editor.show(title: profile.name, size: CGSize(width: 720, height: 760)) {
                ProfileEditor(draft: profile, isNew: isNew, model: model,
                              onSave: { [weak self] in model.saveProfile($0); self?.editor.close() },
                              onDelete: { [weak self] in model.deleteProfile(profile.id); self?.editor.close() },
                              onCancel: { [weak self] in self?.editor.close() })
            }
        }
        model.onEditTrigger = { [weak self, weak model] trigger, isNew in
            guard let self, let model else { return }
            self.editor.show(title: trigger.name, size: CGSize(width: 720, height: 600)) {
                TriggerEditor(draft: trigger, isNew: isNew, model: model,
                              onSave: { [weak self] in model.saveTrigger($0); self?.editor.close() },
                              onDelete: { [weak self] in model.deleteTrigger(trigger.id); self?.editor.close() },
                              onCancel: { [weak self] in self?.editor.close() })
            }
        }
        model.onShowSetup = { [weak self] in self?.showSetup() }
        model.onPlanChange = { [weak self] plan, enabled in self?.updateIcon(plan: plan, enabled: enabled) }
        installStatusItem(model)
        installSignalHandlers()
        model.start()
        updateIcon(plan: model.plan, enabled: model.config.passthroughEnabled)
        if !model.config.setupCompleted { showSetup() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    private func installStatusItem(_ model: MacsKeyBoredModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.toolTip = "MacsKeyBored"
        let menuModel = StatusMenuModel(name: MacsKeyBoredMenu.name) { [weak model] in
            MainActor.assumeIsolated { model.map(MacsKeyBoredMenu.content) ?? StatusMenuContent() }
        }
        menuModel.onSetup = { [weak self] in
            self?.menu?.close()
            self?.showSetup()
        }
        menuModel.onQuit = { NSApp.terminate(nil) }
        menu = StatusMenuController(button: button, model: menuModel)
    }

    private func updateIcon(plan: PassthroughPlan, enabled: Bool) {
        let state: MenuBarGlyph.State = !enabled ? .off : plan.isActive ? .passing : .idle
        statusItem?.button?.image = MenuBarGlyph.image(state)
    }

    /// `kill` and Ctrl-C quit through the same door as ⌘Q, so system shortcuts never stay off.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func openMenu() { menu?.show() }

    func openEditor(_ kind: String) {
        setup.close()
        if kind == "trigger" {
            model?.newTrigger(.typeText)
        } else {
            model?.newProfile(for: KnownPassthroughApps.all[0])
        }
    }

    private func showSetup() {
        guard let model else { return }
        setup.show(title: "Welcome to MacsKeyBored", size: CGSize(width: 560, height: 580)) {
            SetupView(model: model) { [weak self] in
                model.completeSetup()
                self?.setup.close()
                self?.menu?.show()
            }
        }
    }
}
#endif
