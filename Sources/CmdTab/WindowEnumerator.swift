import AppKit
import ApplicationServices
import CoreGraphics

final class WindowEnumerator {
    // Cap on each synchronous AX IPC call. Without it, a hung target app can
    // block the main thread (and the global event tap) until it responds.
    private let messagingTimeout: Float = 0.2

    func visibleWindows() -> [WindowInfo] {
        let index = onScreenIndex()
        return index.orderedPIDs.flatMap { pid in
            windows(for: pid, onScreenFrames: index.framesByPID[pid] ?? [])
        }
    }

    func activate(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.processID)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window.axWindow)
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, window.axWindow)
        AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.processID)?.activate(options: [])
    }

    // On-screen windows belong to the current space; restricting them to the
    // display under the frontmost window keeps the switcher to this monitor.
    private struct OnScreenIndex {
        var orderedPIDs: [pid_t] = []
        var framesByPID: [pid_t: [CGRect]] = [:]
    }

    private func onScreenIndex() -> OnScreenIndex {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return OnScreenIndex()
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates: [(pid: pid_t, bounds: CGRect)] = list.compactMap { entry in
            guard
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                pid != ownPID,
                (entry[kCGWindowLayer as String] as? Int) == 0,
                (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else {
                return nil
            }
            return (pid, bounds)
        }

        guard let focus = candidates.first,
              let monitor = displayBounds(containing: center(of: focus.bounds)) else {
            return OnScreenIndex()
        }

        var index = OnScreenIndex()
        var seen = Set<pid_t>()
        for candidate in candidates where monitor.contains(center(of: candidate.bounds)) {
            if seen.insert(candidate.pid).inserted {
                index.orderedPIDs.append(candidate.pid)
            }
            index.framesByPID[candidate.pid, default: []].append(candidate.bounds)
        }
        return index
    }

    private func displayBounds(containing point: CGPoint) -> CGRect? {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else {
            return nil
        }
        return CGDisplayBounds(displayID)
    }

    private func center(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func windows(for processID: pid_t, onScreenFrames: [CGRect]) -> [WindowInfo] {
        guard !onScreenFrames.isEmpty,
              let app = NSRunningApplication(processIdentifier: processID),
              app.isHidden == false,
              let applicationName = app.localizedName else {
            return []
        }

        let axApp = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else {
            return []
        }

        return axWindows.enumerated().compactMap { index, axWindow in
            AXUIElementSetMessagingTimeout(axWindow, messagingTimeout)
            guard isSwitchable(axWindow),
                  isOnScreen(axWindow, frames: onScreenFrames) else { return nil }

            let title = stringAttribute(kAXTitleAttribute, axWindow)
            return WindowInfo(
                id: "\(processID)-\(index)-\(title)",
                processID: processID,
                applicationName: applicationName,
                title: title,
                icon: app.icon,
                axWindow: axWindow
            )
        }
    }

    private func isSwitchable(_ window: AXUIElement) -> Bool {
        guard !boolAttribute(kAXMinimizedAttribute, window),
              !boolAttribute("AXFullScreen", window),
              let size = sizeAttribute(kAXSizeAttribute, window),
              size.width > 80,
              size.height > 40 else {
            return false
        }

        return true
    }

    private func isOnScreen(_ window: AXUIElement, frames: [CGRect]) -> Bool {
        guard let origin = pointAttribute(kAXPositionAttribute, window),
              let size = sizeAttribute(kAXSizeAttribute, window) else {
            return false
        }

        let frame = CGRect(origin: origin, size: size)
        let tolerance: CGFloat = 5
        return frames.contains { candidate in
            abs(candidate.minX - frame.minX) <= tolerance
                && abs(candidate.minY - frame.minY) <= tolerance
                && abs(candidate.width - frame.width) <= tolerance
                && abs(candidate.height - frame.height) <= tolerance
        }
    }

    private func attributeValue(_ attribute: String, _ element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ attribute: String, _ element: AXUIElement) -> String {
        attributeValue(attribute, element) as? String ?? ""
    }

    private func boolAttribute(_ attribute: String, _ element: AXUIElement) -> Bool {
        (attributeValue(attribute, element) as? Bool) == true
    }

    private func pointAttribute(_ attribute: String, _ element: AXUIElement) -> CGPoint? {
        guard let value = attributeValue(attribute, element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ attribute: String, _ element: AXUIElement) -> CGSize? {
        guard let value = attributeValue(attribute, element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &size) else {
            return nil
        }
        return size
    }
}
