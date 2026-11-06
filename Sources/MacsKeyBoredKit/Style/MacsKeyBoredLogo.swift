#if canImport(AppKit)
import AppKit
import SwiftUI

/// MacsKeyBored's icon, drawn in code in MacsPane's manner: the same slate (or white) tile, with two
/// keycaps on it, a filled blue ⌘ key on the left and an outlined key with the four-pane window
/// mark on the right: a Mac key that reaches the other machine. Follows the colour scheme unless told
/// which face to wear. Geometry is in units of the tile.
struct MacsKeyBoredLogo: View {
    var size: CGFloat = 40
    var face: ColorScheme?
    /// Only the two keys on a clear square: the layer Xcode's icon format stacks on its own fill.
    var marksOnly = false
    @Environment(\.colorScheme) private var scheme

    static let keyBlue = Color(red: 0.04, green: 0.52, blue: 1)

    private var dark: Bool { (face ?? scheme) == .dark }
    private var tileColours: [Color] { dark ? [Color(white: 0.25), Color(white: 0.09)] : [.white, Color(white: 0.89)] }
    private var outlineColour: Color { dark ? Color(white: 0.91) : Color(white: 0.23) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        if marksOnly {
            keys.frame(width: size, height: size)
        } else {
            tile(shape)
        }
    }

    private func tile(_ shape: RoundedRectangle) -> some View {
        ZStack {
            LinearGradient(colors: tileColours, startPoint: .top, endPoint: .bottom)
            keys
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: dark ? [.white.opacity(0.35), .white.opacity(0.02)]
                                                                 : [.black.opacity(0.05), .black.opacity(0.16)],
                                                    startPoint: .top, endPoint: .bottom),
                                    lineWidth: max(0.5, size * 0.0036)))
        .accessibilityLabel("MacsKeyBored")
    }

    /// The ⌘ key in blue, then the outlined key with the four-pane mark.
    private var keys: some View {
            HStack(spacing: size * 0.07) {
                // The Mac key.
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(Self.keyBlue)
                    .overlay(Image(systemName: "command")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(.white))
                    .frame(width: size * 0.34, height: size * 0.34)
                // The other machine's key: four panes in an outlined cap.
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .strokeBorder(outlineColour, lineWidth: max(1, size * 0.04))
                    .overlay(panes.frame(width: size * 0.15, height: size * 0.15))
                    .frame(width: size * 0.34, height: size * 0.34)
            }
    }

    private var panes: some View {
        VStack(spacing: size * 0.016) {
            HStack(spacing: size * 0.016) { pane; pane }
            HStack(spacing: size * 0.016) { pane; pane }
        }
    }

    private var pane: some View {
        Rectangle().fill(outlineColour)
    }

    /// The tile as a bitmap, for the .icns.
    @MainActor static func pngData(size: CGFloat, face: ColorScheme, marksOnly: Bool = false) -> Data? {
        let renderer = ImageRenderer(content: MacsKeyBoredLogo(size: marksOnly ? size : size * 0.8, face: face,
                                                               marksOnly: marksOnly)
            .frame(width: size, height: size))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// The menu-bar icon: a ⌘ key, filled while passthrough is handing keys to an app, outlined while
/// macOS keeps them, and slashed while paused or switched off.
enum MenuBarGlyph {
    enum State { case idle, passing, off }

    static func image(_ state: State) -> NSImage? {
        let name: String
        switch state {
        case .idle: name = "command.square"
        case .passing: name = "command.square.fill"
        case .off: name = "keyboard.badge.ellipsis"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacsKeyBored")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        return image
    }
}
#endif
