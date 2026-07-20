import AppKit
import SwiftUI

@MainActor
final class SwitcherState: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex = -1
    private(set) var revision = 0

    var selectedWindow: WindowInfo? {
        windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
    }

    func replaceWindows(_ newWindows: [WindowInfo]) {
        withoutAnimation {
            windows = newWindows
            selectedIndex = newWindows.count > 1 ? 1 : (newWindows.isEmpty ? -1 : 0)
            revision &+= 1
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

    func select(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        withoutAnimation {
            selectedIndex = index
        }
    }
}

@MainActor
final class SwitcherWindowController: NSWindowController {
    private let enumerator = WindowEnumerator()
    private let state = SwitcherState()
    private let settings = AppSettings()
    private let containerView: NSView
    private var glassView: NSGlassEffectView
    private var installedGlassStyle: SwitcherGlassStyle
    private var glassConstraints: [NSLayoutConstraint] = []
    private var glassContentConstraints: [NSLayoutConstraint] = []
    private var isLivePreviewing = false
    private var activationObserver: NSObjectProtocol?
    private let panelWidth: CGFloat = 600
    private let panelRadius: CGFloat = 14

    init() {
        let rootView = TransparentView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 340))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        let containerView = TransparentView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.layer?.cornerRadius = panelRadius
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true

        let glassView = NSGlassEffectView()
        let glassStyle = settings.switcherGlassStyle
        glassView.style = glassStyle.nsStyle
        glassView.cornerRadius = 0
        glassView.translatesAutoresizingMaskIntoConstraints = false

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
        self.containerView = containerView
        self.glassView = glassView
        self.installedGlassStyle = glassStyle

        super.init(window: window)

        let hostingView = ClearHostingView(rootView: SwitcherView(
            state: state,
            onHover: { [weak self] index in self?.selectIndex(index) },
            onCommit: { [weak self] in self?.commitSelection() }
        ))
        rootView.pin(containerView)
        installGlassView(glassView)
        installContentView(hostingView, in: glassView)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // TODO: In live mode this suppresses dismiss for ALL activations, so
            // an external app activating itself (e.g. user clicks another window)
            // won't auto-dismiss the panel. Fix: track the pid from previewSelection
            // and only skip dismiss when the activated app (note.userInfo's
            // NSWorkspace.applicationUserInfoKey) matches it; reset the pid in dismiss().
            DispatchQueue.main.async {
                guard let self, !self.isLivePreviewing else { return }
                self.dismiss()
            }
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
        applyGlassStyle(settings.switcherGlassStyle)
        state.replaceWindows(enumerator.visibleWindows())
        resizeForContent()
        centerOnActiveScreen()
        isLivePreviewing = settings.isLiveSwitchEnabled
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window?.orderFrontRegardless()
        }
        window?.displayIfNeeded()
        if isLivePreviewing {
            previewSelection()
        }
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

        if isLivePreviewing {
            previewSelection()
        }
    }

    func selectIndex(_ index: Int) {
        guard settings.isMouseSelectionEnabled,
              window?.isVisible == true,
              index != state.selectedIndex else { return }
        state.select(index)
        if isLivePreviewing {
            previewSelection()
        }
    }

    func cancel() {
        dismiss()
    }

    func commitSelection() {
        let selectedWindow = state.selectedWindow
        let wasLivePreviewing = isLivePreviewing
        dismiss()
        // In live mode the selected window is already frontmost from the last
        // preview, so committing only needs to dismiss the panel.
        if !wasLivePreviewing, let selectedWindow {
            enumerator.activate(selectedWindow)
        }
    }

    private func previewSelection() {
        guard let selectedWindow = state.selectedWindow else { return }
        enumerator.activate(selectedWindow)
        window?.orderFrontRegardless()
    }

    private func dismiss() {
        guard window?.isVisible == true else { return }
        isLivePreviewing = false
        close()
        state.replaceWindows([])
    }

    private func applyGlassStyle(_ style: SwitcherGlassStyle) {
        guard style != installedGlassStyle else { return }

        let contentView = glassView.contentView
        glassView.contentView = nil
        NSLayoutConstraint.deactivate(glassContentConstraints)
        NSLayoutConstraint.deactivate(glassConstraints)
        glassView.removeFromSuperview()

        let replacement = makeGlassView(style: style)
        glassView = replacement
        installedGlassStyle = style
        installGlassView(replacement)
        if let contentView {
            installContentView(contentView, in: replacement)
        }
        replacement.needsDisplay = true
        window?.displayIfNeeded()
    }

    private func makeGlassView(style: SwitcherGlassStyle) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = style.nsStyle
        view.cornerRadius = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func installGlassView(_ view: NSGlassEffectView) {
        containerView.addSubview(view)
        glassConstraints = [
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(glassConstraints)
    }

    private func installContentView(_ contentView: NSView, in glassView: NSGlassEffectView) {
        glassView.contentView = contentView
        contentView.translatesAutoresizingMaskIntoConstraints = false
        glassContentConstraints = [
            contentView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: glassView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(glassContentConstraints)
    }

    private func resizeForContent() {
        guard let window else { return }

        let visibleRows = min(max(state.windows.count, 1), 7)
        let height = CGFloat(visibleRows * 30 + 16)
        window.setContentSize(NSSize(width: panelWidth, height: height))
    }

    private func centerOnActiveScreen() {
        guard let window, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

}

private struct SwitcherView: View {
    @ObservedObject var state: SwitcherState
    let onHover: (Int) -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if state.windows.isEmpty {
                Text("No windows")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                    WindowRow(
                        window: window,
                        isSelected: index == state.selectedIndex,
                        onHover: { onHover(index) },
                        onCommit: onCommit
                    )
                }
            }
        }
        .padding(8)
        .background(.clear)
        .animation(nil, value: state.selectedIndex)
        .animation(nil, value: state.revision)
    }
}

private struct WindowRow: View {
    let window: WindowInfo
    let isSelected: Bool
    let onHover: () -> Void
    let onCommit: () -> Void

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
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { onHover() }
        }
        .onTapGesture { onCommit() }
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
