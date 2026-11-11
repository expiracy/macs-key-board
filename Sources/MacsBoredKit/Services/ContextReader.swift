#if canImport(AppKit)
import AppKit
import ApplicationServices
import IOKit.ps
import MacsBoredCore

/// Reads what conditions need, in one go: the front app, its focused window through Accessibility
/// (title, full screen, whether it covers its display), the displays, the power source, the time and
/// Caps Lock. Each Accessibility call is held to a quarter of a second, so a busy app can't stall it.
final class ContextReader {
    func read() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        var context = AppContext(bundleID: app?.bundleIdentifier, appName: app?.localizedName,
                                 processID: app?.processIdentifier)
        if let pid = app?.processIdentifier, AXIsProcessTrusted() {
            readWindow(pid: pid, into: &context)
        }
        let screens = NSScreen.screens
        context.displayCount = screens.count
        context.hasExternalDisplay = screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
        context.onBattery = Self.onBattery()
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        context.minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        context.capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        return context
    }

    private func readWindow(pid: pid_t, into context: inout AppContext) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window: AXUIElement = copy(app, kAXFocusedWindowAttribute) else { return }
        context.windowTitle = copy(window, kAXTitleAttribute)
        context.isFullScreen = (copy(window, "AXFullScreen") as Bool?) ?? false
        if let frame = frame(of: window) {
            context.fillsScreen = Self.axScreenFrames().contains { screen in
                Self.close(frame, screen.full) || Self.close(frame, screen.visible)
            }
        }
    }

    private func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue: AXValue = copy(window, kAXPositionAttribute),
              let sizeValue: AXValue = copy(window, kAXSizeAttribute),
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Every display's frame, and its frame without the menu bar and Dock, in Accessibility's
    /// coordinates (top-left origin on the main display).
    private static func axScreenFrames() -> [(full: CGRect, visible: CGRect)] {
        guard let main = NSScreen.screens.first else { return [] }
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: main.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.map { (flip($0.frame), flip($0.visibleFrame)) }
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 4 && abs(a.minY - b.minY) <= 4 && abs(a.width - b.width) <= 8 && abs(a.height - b.height) <= 8
    }

    private static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
#endif
