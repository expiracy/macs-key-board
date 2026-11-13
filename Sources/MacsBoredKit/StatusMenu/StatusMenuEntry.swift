#if canImport(AppKit)
import AppKit

/// The menu-bar dropdown's content, sorted into the bands `StatusMenuView` draws top to bottom
/// (the same bands as MacsPane's dropdown).
struct StatusMenuContent {
    /// The app's main switch, beside the name.
    var primary: StatusMenuEntry?
    /// What is happening right now; empty draws one quiet line.
    var live: [StatusMenuEntry] = []
    var warnings: [StatusMenuEntry] = []
    /// The general switches and choices.
    var toggles: [StatusMenuEntry] = []
    /// Titled lists, in the order contributed. A long list scrolls in place.
    var groups: [StatusMenuGroup] = []
    /// A line under the name; nil shows the main switch's title.
    var liveFact: String?
}

/// A titled list in the dropdown: its rows, which scroll once there are more than fit, then the
/// commands that always show under them ("New passthrough app").
struct StatusMenuGroup: Identifiable {
    let title: String
    var rows: [StatusMenuEntry]
    var actions: [StatusMenuEntry] = []
    /// The line shown in place of rows when there are none.
    var empty: String?
    /// Set when the rows can be dragged into another order.
    var move: ((Int, Int) -> Void)?
    var id: String { title }
}

/// One line of the menu-bar dropdown (`StatusMenuView` draws them).
struct StatusMenuEntry: Identifiable {
    enum Kind {
        /// What is happening now, one fact about it, and the one thing you would do to it from here.
        case live(fact: String, actionTitle: String?, accent: Bool)
        /// A setting with a few named values, shown side by side; `selected` indexes `options`.
        case choice(options: [String], selected: Int)
        /// A setting that stays put: the row's switch is its one target and the dropdown stays open.
        case toggle(isOn: Bool, disabled: Bool, primary: Bool)
        /// Something done once; the dropdown closes. `danger` is a last-resort command.
        case command(danger: Bool)
        /// A feature that is on but cannot run, with the one click that fixes it.
        case warning(actionTitle: String?)
    }

    let title: String
    var symbol: String?
    let kind: Kind
    var action: (() -> Void)?
    /// A choice's pick, by index into its options.
    var select: ((Int) -> Void)?
    /// A row's second button, at its end (the pencil). The dropdown closes first.
    var secondary: (symbol: String, help: String, action: () -> Void)?
    /// A row's trash button: deletes once a second click confirms it. The dropdown stays open.
    var trash: (help: String, action: () -> Void)?
    /// An app's own icon, drawn in place of the symbol tile.
    var appIcon: NSImage?
    /// Identity when titles can repeat; nil uses the title.
    var key: String?
    /// A command that leaves the dropdown open.
    var keepsOpen = false
    /// Quiet text at the row's end: its keys ("⌃⌥P") or a count.
    var trailing: String?

    var id: String { key ?? title }

    static func live(_ title: String, symbol: String, fact: String, actionTitle: String? = nil,
                     accent: Bool = false, key: String? = nil, action: (() -> Void)? = nil) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol,
                        kind: .live(fact: fact, actionTitle: actionTitle, accent: accent), action: action, key: key)
    }

    static func choice(_ title: String, symbol: String, options: [String], selected: Int,
                       select: @escaping (Int) -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol, kind: .choice(options: options, selected: selected),
                        select: select)
    }

    static func toggle(_ title: String, symbol: String, isOn: Bool, disabled: Bool = false, primary: Bool = false,
                       key: String? = nil,
                       secondary: (symbol: String, help: String, action: () -> Void)? = nil,
                       trash: (help: String, action: () -> Void)? = nil,
                       action: @escaping () -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol,
                        kind: .toggle(isOn: isOn, disabled: disabled, primary: primary), action: action,
                        secondary: secondary, trash: trash, key: key)
    }

    static func command(_ title: String, symbol: String, danger: Bool = false, key: String? = nil,
                        keepsOpen: Bool = false,
                        secondary: (symbol: String, help: String, action: () -> Void)? = nil,
                        trash: (help: String, action: () -> Void)? = nil,
                        action: @escaping () -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol, kind: .command(danger: danger), action: action,
                        secondary: secondary, trash: trash, key: key, keepsOpen: keepsOpen)
    }

    static func warning(_ title: String, actionTitle: String? = nil,
                        action: (() -> Void)? = nil) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: "exclamationmark.triangle",
                        kind: .warning(actionTitle: actionTitle), action: action)
    }
}
#endif
