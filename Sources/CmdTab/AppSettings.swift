import AppKit

struct AppSettings {
    static let liveSwitchDefaultsKey = "liveSwitchEnabled"

    let keyCode: CGKeyCode = 48
    let modifierFlags: CGEventFlags = .maskCommand

    var isLiveSwitchEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.liveSwitchDefaultsKey)
    }

    var displayString: String {
        "\(modifierDisplayString)\(keyDisplayString(for: keyCode))"
    }

    private var modifierDisplayString: String {
        var parts: [String] = []
        if modifierFlags.contains(.maskControl) { parts.append("⌃") }
        if modifierFlags.contains(.maskAlternate) { parts.append("⌥") }
        if modifierFlags.contains(.maskShift) { parts.append("⇧") }
        if modifierFlags.contains(.maskCommand) { parts.append("⌘") }
        return parts.joined()
    }
}

let ShortcutModifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

func keyDisplayString(for keyCode: CGKeyCode) -> String {
    switch keyCode {
    case 48: return "⇥"
    case 36: return "↩"
    case 53: return "Esc"
    case 49: return "Space"
    case 51: return "⌫"
    default:
        return KeyCodeCharacters.map[Int(keyCode)] ?? "Key \(keyCode)"
    }
}

private enum KeyCodeCharacters {
    static let map: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`"
    ]
}
