import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var switcherWindowController: SwitcherWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var settings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuBarItem()

        let controller = SwitcherWindowController()
        switcherWindowController = controller

        PermissionManager.shared.requestStartupPermissions()
        startShortcutMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func showSwitcher() {
        switcherWindowController?.show()
    }

    @objc private func showStatus() {
        PermissionManager.shared.requestStartupPermissions()
        if shortcutMonitor?.isRunning == true {
            showDiagnostics()
        } else {
            reportShortcutMonitorStatus()
        }
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.shared.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(settings: settings)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = settings.displayString
        item.button?.toolTip = "CmdTab"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show CmdTab", action: #selector(showSwitcher), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Status", action: #selector(showStatus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func startShortcutMonitor() {
        let monitor = GlobalShortcutMonitor(settings: settings)
        monitor.isSwitcherVisible = { [weak self] in
            self?.switcherWindowController?.window?.isVisible == true
        }
        monitor.onShortcut = { [weak self] direction in
            guard let self else { return }
            if self.switcherWindowController?.window?.isVisible == true {
                self.switcherWindowController?.cycleSelection(direction)
            } else {
                self.switcherWindowController?.show()
            }
        }
        monitor.onCancel = { [weak self] in
            self?.switcherWindowController?.cancel()
        }
        monitor.onCommit = { [weak self] in
            self?.switcherWindowController?.commitSelection()
        }
        monitor.start()
        shortcutMonitor = monitor
        reportShortcutMonitorStatus()
    }

    private func reportShortcutMonitorStatus() {
        guard shortcutMonitor?.isRunning != true else { return }

        let alert = NSAlert()
        alert.messageText = "CmdTab cannot see global keystrokes"
        alert.informativeText = "Grant Accessibility permission to CmdTab, then quit and reopen it if macOS does not apply the permission immediately."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PermissionManager.shared.openAccessibilitySettings()
        }
    }

    @objc private func showDiagnostics() {
        let alert = NSAlert()
        alert.messageText = "CmdTab diagnostics"
        alert.informativeText = """
        Accessibility trusted: \(PermissionManager.shared.isAccessibilityTrusted)
        Event tap running: \(shortcutMonitor?.isRunning == true)
        Events seen: \(shortcutMonitor?.eventCount ?? 0)
        Shortcut: \(settings.displayString)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
