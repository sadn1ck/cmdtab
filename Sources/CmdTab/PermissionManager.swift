import AppKit
import ApplicationServices

final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestStartupPermissions() {
        requestAccessibilityIfNeeded()
    }

    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityTrusted else { return }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        openPrivacySettingsPane("Privacy_Accessibility")
    }

    private func openPrivacySettingsPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
