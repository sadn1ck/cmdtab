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
        let contentView = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 780, height: 520))
        contentView.style = .regular
        contentView.cornerRadius = 0

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
        contentView.contentView = hostingView
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
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

    @State private var selection: SettingsTab? = .config
    @State private var accessibilityTrusted = PermissionManager.shared.isAccessibilityTrusted

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            NavigationSplitView {
                List(SettingsTab.allCases, selection: $selection) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            } detail: {
                detail
            }
        }
        .background(.clear)
        .onAppear(perform: refreshPermissions)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .config {
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

private struct ConfigPane: View {
    let shortcut: String
    let accessibilityTrusted: Bool
    let refreshPermissions: () -> Void

    @AppStorage(AppSettings.liveSwitchDefaultsKey) private var liveSwitch = false
    @AppStorage(AppSettings.mouseSelectionDefaultsKey)
    private var mouseSelection = AppSettings.defaultMouseSelectionEnabled
    @AppStorage(AppSettings.switcherGlassStyleDefaultsKey)
    private var switcherGlassStyle = AppSettings.defaultSwitcherGlassStyle.rawValue

    var body: some View {
        SettingsPane {
            PaneHeader(icon: "command", title: "Config", subtitle: "Switcher behavior and required permissions.")

            SettingsCard {
                PickerRow(
                    icon: "sparkles",
                    title: "Switcher glass",
                    selection: $switcherGlassStyle
                )
            }

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
                ToggleRow(
                    icon: "eye",
                    title: "Live preview switching",
                    subtitle: "Switch to the highlighted window on every Cmd-Tab",
                    isOn: $liveSwitch
                )
                Divider()
                ToggleRow(
                    icon: "cursorarrow.motionlines",
                    title: "Mouse selection",
                    subtitle: "Select a window when the pointer moves over it",
                    isOn: $mouseSelection
                )
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PickerRow: View {
    let icon: String
    let title: String
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(SwitcherGlassStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 150)
        }
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 38)
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

private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 42)
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
                .buttonStyle(.glass)
        }
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 34)
    }
}
