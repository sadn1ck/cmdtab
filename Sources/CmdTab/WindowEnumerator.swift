import AppKit
import ApplicationServices
import CoreGraphics

final class WindowEnumerator {
    func visibleWindows() -> [WindowInfo] {
        orderedProcessIDs().flatMap(windows)
    }

    func activate(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.processID)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window.axWindow)
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, window.axWindow)
        AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.processID)?.activate(options: [.activateAllWindows])
    }

    private func orderedProcessIDs() -> [pid_t] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        var result: [pid_t] = []

        for entry in list {
            guard
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                pid != ownPID,
                (entry[kCGWindowLayer as String] as? Int) == 0,
                (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                seen.insert(pid).inserted
            else {
                continue
            }

            result.append(pid)
        }

        return result
    }

    private func windows(for processID: pid_t) -> [WindowInfo] {
        guard let app = NSRunningApplication(processIdentifier: processID),
              app.isHidden == false,
              let applicationName = app.localizedName else {
            return []
        }

        let axApp = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else {
            return []
        }

        return axWindows.enumerated().compactMap { index, axWindow in
            guard isSwitchable(axWindow) else { return nil }

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

    private func stringAttribute(_ attribute: String, _ element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private func boolAttribute(_ attribute: String, _ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) == true
    }

    private func sizeAttribute(_ attribute: String, _ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((axValue as! AXValue), .cgSize, &size) else {
            return nil
        }
        return size
    }
}
