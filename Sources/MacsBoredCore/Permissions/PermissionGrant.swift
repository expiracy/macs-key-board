import CoreGraphics
import Foundation

/// The system permissions MacsBored asks for, and what granting one takes. Today that is one:
/// Accessibility, which seeing keys before macOS acts on them needs. One description per permission,
/// so the menu's warning, the setup step and the permission dropdown all say the same thing.
public enum PermissionGrant: String, CaseIterable, Sendable, Identifiable {
    case accessibility

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        }
    }

    /// The pane's key in the Privacy & Security deep link.
    public var paneKey: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        }
    }

    public var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(paneKey)")
    }

    /// The service name `tccutil` knows this permission by, for replacing a stale entry left in
    /// System Settings by an earlier copy of the app.
    public var tccService: String {
        switch self {
        case .accessibility: "Accessibility"
        }
    }

    /// The line that explains a switch that is already on but not working.
    public func staleEntryHint(appName: String) -> String {
        "Switched on but still not working? That entry belongs to an earlier copy of \(appName). "
            + "Start over replaces it."
    }
}

/// One window in the window server's roster, as the permission dropdown needs it to find System Settings.
public struct ProcessWindowInfo: Equatable, Sendable {
    public let id: UInt32
    public let ownerPid: Int32
    /// Global frame in the window server's top-left-origin coordinates.
    public let frame: CGRect
    public let isOnScreen: Bool
    public let layer: Int

    public init(id: UInt32, ownerPid: Int32, frame: CGRect, isOnScreen: Bool, layer: Int) {
        self.id = id
        self.ownerPid = ownerPid
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.layer = layer
    }
}

extension CGRect {
    /// This rect, from the window server's top-left origin into AppKit's bottom-left one (or back).
    public func flipped(primaryHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}
