// swift-tools-version: 5.10
import PackageDescription

// MacsKeyBored, hand macOS's own shortcuts to the apps that should have them (Windows App, Citrix
// Viewer, a virtual machine) and run your own triggers everywhere else.
//   • MacsKeyBoredCore, pure logic (profiles, conditions, triggers, the passthrough plan, config)
//                       and its tests. No AppKit.
//   • MacsKeyBoredKit , the AppKit/SwiftUI app: the event tap, the system-shortcut switch, the
//                       menu-bar dropdown, the editors and setup.
//   • macskeybored    , the executable that boots it: `swift run macskeybored`.
// The signed .app is built by Xcode from project.yml and reuses MacsKeyBoredKit.
let package = Package(
    name: "MacsKeyBored",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacsKeyBoredCore", targets: ["MacsKeyBoredCore"]),
        .library(name: "MacsKeyBoredKit", targets: ["MacsKeyBoredKit"]),
        .executable(name: "macskeybored", targets: ["MacsKeyBored"]),
    ],
    targets: [
        .target(name: "MacsKeyBoredCore"),
        .target(name: "MacsKeyBoredKit", dependencies: ["MacsKeyBoredCore"]),
        .executableTarget(name: "MacsKeyBored", dependencies: ["MacsKeyBoredKit"]),
        .testTarget(name: "MacsKeyBoredCoreTests", dependencies: ["MacsKeyBoredCore"]),
    ]
)
