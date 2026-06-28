import AppKit
import ApplicationServices

final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var canListenToInput: Bool {
        CGPreflightListenEventAccess()
    }

    func requestStartupPermissions() {
        requestAccessibilityIfNeeded()
        requestInputMonitoringIfNeeded()
    }

    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityTrusted else { return }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoringIfNeeded() {
        guard !canListenToInput else { return }
        CGRequestListenEventAccess()
    }

    func openAccessibilitySettings() {
        openPrivacySettingsPane("Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacySettingsPane("Privacy_ListenEvent")
    }

    private func openPrivacySettingsPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
