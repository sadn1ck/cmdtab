import AppKit
import ApplicationServices

struct WindowInfo: Identifiable {
    let id: String
    let processID: pid_t
    let applicationName: String
    let title: String
    let icon: NSImage?
    let axWindow: AXUIElement

    var displayTitle: String {
        title.isEmpty ? applicationName : "\(title) / \(applicationName)"
    }
}
