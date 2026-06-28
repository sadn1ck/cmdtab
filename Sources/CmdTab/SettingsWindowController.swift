import AppKit
import Security
import SwiftUI

enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, build != short { return "\(short) (\(build))" }
        return short
    }

    static var signingAuthority: String {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return "Unknown" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "Unsigned" }
        if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first {
            var commonName: CFString?
            if SecCertificateCopyCommonName(leaf, &commonName) == errSecSuccess, let name = commonName as String? {
                return name
            }
        }
        return "Ad-hoc"
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings) {
        let contentView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 780, height: 520))
        contentView.material = .underWindowBackground
        contentView.blendingMode = .behindWindow
        contentView.state = .active

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "CmdTab Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.minSize = NSSize(width: 760, height: 420)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.center()

        super.init(window: window)

        let hostingView = NSHostingView(rootView: SettingsView(settings: settings))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.pin(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case config = "Config"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .config: "switch.2"
        case .about: "info.circle"
        }
    }
}

private struct SettingsView: View {
    let settings: AppSettings

    @State private var selection: SettingsTab = .config
    @State private var accessibilityTrusted = PermissionManager.shared.isAccessibilityTrusted

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 210)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.clear)
        .onAppear(perform: refreshPermissions)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .config:
            ConfigPane(
                shortcut: settings.displayString,
                accessibilityTrusted: accessibilityTrusted,
                refreshPermissions: refreshPermissions
            )
        case .about:
            AboutPane()
        }
    }

    private func refreshPermissions() {
        accessibilityTrusted = PermissionManager.shared.isAccessibilityTrusted
    }
}

private struct SidebarView: View {
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 22)

            ForEach(SettingsTab.allCases) { tab in
                SidebarItem(tab: tab, isSelected: selection == tab) {
                    selection = tab
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 32, height: 32)
                    .symbolVariant(.none)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .foregroundStyle(isSelected ? .white : .primary)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ConfigPane: View {
    let shortcut: String
    let accessibilityTrusted: Bool
    let refreshPermissions: () -> Void

    var body: some View {
        SettingsPane {
            PaneHeader(icon: "command", title: "Config", subtitle: "Switcher behavior and required permissions.")

            SettingsCard {
                InfoRow(icon: "keyboard", title: "Shortcut", value: shortcut)
                Divider()
                InfoRow(icon: "arrow.right.arrow.left", title: "Cycle forward", value: "Cmd-Tab")
                Divider()
                InfoRow(icon: "arrow.left.arrow.right", title: "Cycle backward", value: "Cmd-Shift-Tab")
                Divider()
                InfoRow(icon: "return", title: "Commit", value: "Release Cmd")
                Divider()
                InfoRow(icon: "escape", title: "Cancel", value: "Esc")
            }

            SettingsCard {
                PermissionRow(title: "Accessibility", isGranted: accessibilityTrusted) {
                    PermissionManager.shared.openAccessibilitySettings()
                }
            }

            Button("Refresh Permissions", action: refreshPermissions)
                .controlSize(.small)
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        SettingsPane {
            PaneHeader(icon: "rectangle.2.swap", title: "CmdTab", subtitle: "A fast native window switcher for macOS.")

            SettingsCard {
                InfoRow(icon: "app", title: "Version", value: AppInfo.version)
                Divider()
                InfoRow(icon: "number", title: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "com.sadn1ck.apps.cmdtab")
                Divider()
                InfoRow(icon: "lock.shield", title: "Signing", value: AppInfo.signingAuthority)
            }

            SettingsCard {
                InfoRow(icon: "sparkles", title: "Interface", value: "SwiftUI + AppKit")
                Divider()
                InfoRow(icon: "bolt", title: "Preview rendering", value: "Disabled for speed")
            }

        }
    }
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: 520, alignment: .topLeading)
            .padding(.leading, 32)
            .padding(.trailing, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PaneHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}

private struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .frame(width: 18)
                .foregroundStyle(isGranted ? .green : .orange)
            Text(title)
            Spacer()
            Text(isGranted ? "Granted" : "Needed")
                .foregroundStyle(.secondary)
            Button("Open", action: openSettings)
                .controlSize(.small)
        }
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 34)
    }
}
