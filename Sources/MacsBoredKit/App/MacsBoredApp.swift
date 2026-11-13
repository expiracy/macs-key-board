#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// MacsBored: a menu-bar app that hands macOS's own shortcuts to the apps that should have them
/// (Windows App, Citrix Viewer, a VM) and runs your own triggers everywhere else. One boot path for
/// `swift run macsbored` and the bundled app.
///
///   path | check [file] | schema   For scripts and agents: print where config.json is, check a
///                     file (each problem with its line; exit 1 on an error), or print its schema.
///   --smoke-test      Boot, then quit after ~1.5 s: a launch check.
///   --export-icon <dir>   Write the icon's PNGs (for scripts/make_icon.sh) and quit.
///   --open-menu       Open the dropdown once launched.
///   --open-editor remap|open|shortcut|passthrough   Open the editor on a new entry on that tab.
///   --open-setup      Open first-time setup.
public enum MacsBoredApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        let url = (try? MacsBoredPaths.configURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-config.json")
        if let outcome = ConfigCommand.run(Array(arguments.dropFirst()), defaultURL: url) {
            FileHandle.standardOutput.write(Data((outcome.output + "\n").utf8))
            exit(outcome.status)
        }
        if let index = arguments.firstIndex(of: "--export-icon"), index + 1 < arguments.count {
            MainActor.assumeIsolated { exportIcon(to: URL(fileURLWithPath: arguments[index + 1])) }
            return
        }
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { MacsBoredAppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            MainActor.assumeIsolated {
                if arguments.contains("--open-menu") { delegate.openMenu() }
                if let index = arguments.firstIndex(of: "--open-editor"), index + 1 < arguments.count {
                    delegate.openEditor(arguments[index + 1])
                }
                if arguments.contains("--open-setup") { delegate.openSetup() }
            }
        }
        if arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("MacsBored: smoke-test OK: launched cleanly, shutting down")
                NSApp.terminate(nil)
            }
        }
        app.run()
    }

    @MainActor private static func exportIcon(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            if let data = MacsBoredLogo.pngData(size: CGFloat(size), face: .light) {
                try? data.write(to: directory.appendingPathComponent("icon_\(size).png"))
            }
        }
        // The layers of App/AppIcon.icon, one per appearance.
        for (face, name) in [(ColorScheme.light, "marks-light"), (.dark, "marks-dark")] {
            if let data = MacsBoredLogo.pngData(size: 1024, face: face, marksOnly: true) {
                try? data.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }
}

/// The composition root: the config file, the model, the menu-bar icon and its dropdown, the editors
/// and setup. Quitting, or a TERM or INT signal, puts every macOS shortcut back first.
@MainActor
final class MacsBoredAppDelegate: NSObject, NSApplicationDelegate {
    private var model: MacsBoredModel?
    private var statusItem: NSStatusItem?
    private var menu: StatusMenuController?
    private let editor = EditorWindowController()
    private let setup = EditorWindowController()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let url = (try? MacsBoredPaths.configURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-config.json")
        let model = MacsBoredModel(store: MacsBoredConfigStore(url: url, legacyURL: try? MacsBoredPaths.legacyConfigURL()))
        self.model = model
        model.onEdit = { [weak self] draft in self?.edit(draft) }
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

    private func installStatusItem(_ model: MacsBoredModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.toolTip = "MacsBored"
        let menuModel = StatusMenuModel(name: MacsBoredMenu.name) { [weak model] in
            MainActor.assumeIsolated { model.map(MacsBoredMenu.content) ?? StatusMenuContent() }
        }
        menuModel.onSetup = { [weak self] in
            self?.menu?.close()
            self?.showSetup()
        }
        menuModel.onNew = { [weak self, weak model] in
            self?.menu?.close()
            model?.newEntry()
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

    func openEditor(_ tab: String) {
        setup.close()
        var draft = EntryDraft()
        draft.tab = EntryDraft.Tab(rawValue: tab) ?? .remap
        edit(draft)
    }

    func openSetup() { showSetup() }

    private func edit(_ draft: EntryDraft) {
        guard let model else { return }
        let isNew = draft.origin == .new
        editor.show(title: isNew ? "New" : draft.name, size: CGSize(width: EntryEditor.width, height: 640), fitsContent: true) {
            EntryEditor(draft: draft, isNew: isNew, model: model,
                        onSave: { [weak self] result in model.save(result, replacing: draft.origin); self?.editor.close() },
                        onDelete: { [weak self] in model.delete(draft.origin); self?.editor.close() },
                        onCancel: { [weak self] in self?.editor.close() })
        }
    }

    private func showSetup() {
        guard let model else { return }
        setup.show(title: "Set up MacsBored", size: SetupView.size) {
            SetupView(model: model) { [weak self] in
                model.completeSetup()
                self?.setup.close()
                self?.menu?.show()
            }
        }
    }
}
#endif
