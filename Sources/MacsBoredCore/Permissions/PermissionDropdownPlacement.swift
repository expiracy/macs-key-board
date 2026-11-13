import CoreGraphics

/// Where the permission dropdown hangs: under the System Settings window, so the app icon you drag is
/// right below the list it goes into. Pure, in AppKit's bottom-left space.
public enum PermissionDropdownPlacement {
    /// Space between the Settings window's bottom edge (or the menu bar) and the dropdown.
    public static let gap: CGFloat = 10
    /// How far inside the Settings window it sits when the screen has no room below the window.
    public static let inset: CGFloat = 16
    /// The least distance from a screen edge.
    public static let margin: CGFloat = 8

    /// Smallest window that counts as the Settings window rather than a sheet or a sliver.
    static let minimumWindow = CGSize(width: 300, height: 200)

    /// Centred under `settingsWindow`; tucked inside its bottom edge when the screen has no room below
    /// it; dropping from the top of the screen while Settings has not opened yet. Always on screen.
    public static func frame(size: CGSize, settingsWindow: CGRect?, visibleFrame: CGRect) -> CGRect {
        let midX: CGFloat
        let minY: CGFloat
        if let settings = settingsWindow {
            midX = settings.midX
            let below = settings.minY - gap - size.height
            minY = below >= visibleFrame.minY + margin ? below : settings.minY + inset
        } else {
            midX = visibleFrame.midX
            minY = visibleFrame.maxY - gap - size.height
        }
        let x = min(max(midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - margin - size.width)
        let y = min(max(minY, visibleFrame.minY + margin), visibleFrame.maxY - margin - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// The System Settings window among the window server's roster (front to back): the front-most
    /// on-screen, ordinary-layer window of its process that is big enough to be the main window.
    public static func settingsWindow(in roster: [ProcessWindowInfo], ownerPid: Int32) -> ProcessWindowInfo? {
        roster.first { window in
            window.ownerPid == ownerPid && window.isOnScreen && window.layer == 0
                && window.frame.width >= minimumWindow.width && window.frame.height >= minimumWindow.height
        }
    }
}
