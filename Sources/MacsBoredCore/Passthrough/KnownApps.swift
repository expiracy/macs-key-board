import Foundation

/// Apps that show another computer's screen, offered first when adding a passthrough app.
public enum KnownPassthroughApps {
    public static let all: [AppRef] = [
        AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App"),
        AppRef(bundleID: "com.citrix.receiver.icaviewer.mac", name: "Citrix Viewer"),
        AppRef(bundleID: "com.vmware.horizon", name: "Omnissa Horizon Client"),
        AppRef(bundleID: "com.parallels.desktop.console", name: "Parallels Desktop"),
        AppRef(bundleID: "com.vmware.fusion", name: "VMware Fusion"),
        AppRef(bundleID: "com.utmapp.UTM", name: "UTM"),
        AppRef(bundleID: "com.p5sys.jump.mac.viewer", name: "Jump Desktop"),
        AppRef(bundleID: "com.realvnc.vncviewer", name: "VNC Viewer"),
        AppRef(bundleID: "com.amazon.workspaces", name: "Amazon WorkSpaces"),
        AppRef(bundleID: "com.lemonmojo.RoyalTSX.App", name: "Royal TSX"),
    ]
}

extension KnownPassthroughApps {
    /// A known app's name, for a config file that names it by bundle ID alone.
    public static func name(for bundleID: String) -> String? {
        all.first { $0.bundleID == bundleID }?.name
    }
}
