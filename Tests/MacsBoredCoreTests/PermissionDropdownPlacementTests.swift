import Testing
import CoreGraphics
@testable import MacsBoredCore

// A 1512×982 laptop screen (AppKit, bottom-left) under a 38-pt menu bar, and a dropdown 360×96.
private let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
private let size = CGSize(width: 360, height: 96)

@Test func theDropdownHangsCentredUnderTheSettingsWindow() {
    let settings = CGRect(x: 400, y: 300, width: 700, height: 600)
    let frame = PermissionDropdownPlacement.frame(size: size, settingsWindow: settings, visibleFrame: visible)
    #expect(frame.midX == settings.midX)
    #expect(frame.maxY == settings.minY - PermissionDropdownPlacement.gap)
    #expect(frame.size == size)
}

@Test func withNoRoomBelowItTucksInsideTheWindowsBottomEdge() {
    let settings = CGRect(x: 400, y: 20, width: 700, height: 900)
    let frame = PermissionDropdownPlacement.frame(size: size, settingsWindow: settings, visibleFrame: visible)
    #expect(frame.minY >= visible.minY)
    #expect(frame.minY == settings.minY + PermissionDropdownPlacement.inset)
    #expect(frame.midX == settings.midX)
}

@Test func itStaysOnScreenWhenTheWindowHangsOffAnEdge() {
    let settings = CGRect(x: -500, y: 300, width: 700, height: 600)
    let frame = PermissionDropdownPlacement.frame(size: size, settingsWindow: settings, visibleFrame: visible)
    #expect(frame.minX == visible.minX + PermissionDropdownPlacement.margin)
}

@Test func beforeSettingsOpensItDropsFromTheTopOfTheScreen() {
    let frame = PermissionDropdownPlacement.frame(size: size, settingsWindow: nil, visibleFrame: visible)
    #expect(frame.midX == visible.midX)
    #expect(frame.maxY == visible.maxY - PermissionDropdownPlacement.gap)
}

@Test func theSettingsWindowIsItsFrontMostRealWindow() {
    func window(_ id: UInt32, pid: Int32, layer: Int = 0, frame: CGRect, onScreen: Bool = true) -> ProcessWindowInfo {
        ProcessWindowInfo(id: id, ownerPid: pid, frame: frame, isOnScreen: onScreen, layer: layer)
    }
    let roster = [window(1, pid: 9, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),             // another app
                  window(2, pid: 7, layer: 25, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),   // its menu
                  window(3, pid: 7, frame: CGRect(x: 0, y: 0, width: 40, height: 30)),                // a sliver
                  window(4, pid: 7, frame: CGRect(x: 10, y: 0, width: 800, height: 600), onScreen: false),
                  window(5, pid: 7, frame: CGRect(x: 100, y: 80, width: 715, height: 640))]
    #expect(PermissionDropdownPlacement.settingsWindow(in: roster, ownerPid: 7)?.id == 5)
    #expect(PermissionDropdownPlacement.settingsWindow(in: roster, ownerPid: 42) == nil)
}
