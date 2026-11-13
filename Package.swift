// swift-tools-version: 5.10
import PackageDescription

// MacsBored, hand macOS's own shortcuts to the apps that should have them (Windows App, Citrix
// Viewer, a virtual machine) and run your own triggers everywhere else.
//   • MacsBoredCore, pure logic (profiles, conditions, triggers, the passthrough plan, config)
//                       and its tests. No AppKit.
//   • MacsBoredKit , the AppKit/SwiftUI app: the event tap, the system-shortcut switch, the
//                       menu-bar dropdown, the editors and setup.
//   • macsbored    , the executable that boots it: `swift run macsbored`.
// The signed .app is built by Xcode from project.yml and reuses MacsBoredKit.
let package = Package(
    name: "MacsBored",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacsBoredCore", targets: ["MacsBoredCore"]),
        .library(name: "MacsBoredKit", targets: ["MacsBoredKit"]),
        .executable(name: "macsbored", targets: ["MacsBored"]),
    ],
    targets: [
        .target(name: "MacsBoredCore"),
        .target(name: "MacsBoredKit", dependencies: ["MacsBoredCore"]),
        .executableTarget(name: "MacsBored", dependencies: ["MacsBoredKit"]),
        .testTarget(name: "MacsBoredCoreTests", dependencies: ["MacsBoredCore"]),
    ]
)
