import AppKit
import CoreGraphics

final class GlobalShortcutMonitor {
    var settings: AppSettings
    var onShortcut: ((ShortcutDirection) -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?
    var isSwitcherVisible: (() -> Bool)?

    private(set) var isRunning = false
    private(set) var eventCount = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
                return monitor.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            isRunning = false
            return
        }

        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        eventCount += 1

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == 53, isSwitcherVisible?() == true {
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            return nil
        }

        guard keyCode == settings.keyCode, modifierFlags(event.flags).contains(settings.modifierFlags) else {
            return Unmanaged.passUnretained(event)
        }

        let direction: ShortcutDirection = isReverseShortcut(event.flags) ? .backward : .forward
        DispatchQueue.main.async { [weak self] in self?.onShortcut?(direction) }
        return nil
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == settings.keyCode, isSwitcherVisible?() == true else {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard isSwitcherVisible?() == true,
              !modifierFlags(event.flags).contains(settings.modifierFlags) else {
            return
        }

        DispatchQueue.main.async { [weak self] in self?.onCommit?() }
    }

    private func modifierFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(ShortcutModifierMask)
    }

    private func isReverseShortcut(_ flags: CGEventFlags) -> Bool {
        modifierFlags(flags).contains(.maskShift) && !settings.modifierFlags.contains(.maskShift)
    }
}

enum ShortcutDirection {
    case forward
    case backward
}
