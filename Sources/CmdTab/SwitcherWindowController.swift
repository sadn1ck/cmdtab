import AppKit
import SwiftUI

@MainActor
final class SwitcherState: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex = -1

    var selectedWindow: WindowInfo? {
        windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
    }

    func replaceWindows(_ newWindows: [WindowInfo]) {
        withoutAnimation {
            windows = newWindows
            selectedIndex = newWindows.count > 1 ? 1 : (newWindows.isEmpty ? -1 : 0)
        }
    }

    func cycle() {
        guard !windows.isEmpty else { return }
        withoutAnimation {
            selectedIndex = (selectedIndex + 1) % windows.count
        }
    }

    func cycleBackward() {
        guard !windows.isEmpty else { return }
        withoutAnimation {
            selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        }
    }
}

@MainActor
final class SwitcherWindowController: NSWindowController {
    private let enumerator = WindowEnumerator()
    private let state = SwitcherState()
    private var activationObserver: NSObjectProtocol?
    private let panelWidth: CGFloat = 600
    private let transparentInset: CGFloat = 10
    private let panelRadius: CGFloat = 14

    init() {
        let rootView = TransparentView(frame: NSRect(x: 0, y: 0, width: panelWidth + transparentInset * 2, height: 340))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        let shadowView = TransparentView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.wantsLayer = true
        shadowView.layer?.backgroundColor = NSColor.clear.cgColor
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = 0.24
        shadowView.layer?.shadowRadius = 22
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -8)

        let glassView = NSVisualEffectView()
        glassView.material = .menu
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = panelRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        glassView.layer?.borderWidth = 0.8
        glassView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor

        let window = NSPanel(
            contentRect: rootView.frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = rootView

        super.init(window: window)

        let hostingView = ClearHostingView(rootView: SwitcherView(state: state))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(shadowView)
        shadowView.addSubview(glassView)
        glassView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: transparentInset),
            shadowView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -transparentInset),
            shadowView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: transparentInset),
            shadowView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -transparentInset),
            glassView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
        ])

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.dismiss() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func show() {
        state.replaceWindows(enumerator.visibleWindows())
        resizeForContent()
        centerOnActiveScreen()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window?.orderFrontRegardless()
        }
        window?.displayIfNeeded()
    }

    func cycleSelection(_ direction: ShortcutDirection) {
        if window?.isVisible != true {
            show()
            return
        }

        switch direction {
        case .forward:
            state.cycle()
        case .backward:
            state.cycleBackward()
        }
    }

    func cancel() {
        dismiss()
    }

    func commitSelection() {
        let selectedWindow = state.selectedWindow
        dismiss()
        if let selectedWindow {
            enumerator.activate(selectedWindow)
        }
    }

    private func dismiss() {
        guard window?.isVisible == true else { return }
        close()
        state.replaceWindows([])
    }

    private func resizeForContent() {
        guard let window else { return }

        let visibleRows = min(max(state.windows.count, 1), 7)
        let height = CGFloat(visibleRows * 30 + 16) + transparentInset * 2
        window.setContentSize(NSSize(width: panelWidth + transparentInset * 2, height: height))
        updateShadowPath()
    }

    private func centerOnActiveScreen() {
        guard let window, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

    private func updateShadowPath() {
        guard let rootView = window?.contentView,
              let shadowView = rootView.subviews.first else {
            return
        }

        shadowView.layoutSubtreeIfNeeded()
        let path = CGPath(
            roundedRect: shadowView.bounds,
            cornerWidth: panelRadius,
            cornerHeight: panelRadius,
            transform: nil
        )
        shadowView.layer?.shadowPath = path
    }
}

private struct SwitcherView: View {
    @ObservedObject var state: SwitcherState

    var body: some View {
        VStack(spacing: 4) {
            if state.windows.isEmpty {
                Text("No windows")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                    WindowRow(window: window, isSelected: index == state.selectedIndex)
                }
            }
        }
        .padding(8)
        .background(.clear)
        .animation(nil, value: state.selectedIndex)
        .animation(nil, value: state.windows.map(\.id))
    }
}

private struct WindowRow: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            Text(window.displayTitle)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.001))
        }
        .contentShape(Rectangle())
    }
}

@MainActor
private func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

private final class TransparentView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {}
}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
