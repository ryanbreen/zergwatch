import Foundation

enum KeyCodes {
    private static let names: [Int: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        10: "ISO",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "Return",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "⇥",
        49: "Space",
        50: "`",
        51: "Delete",
        53: "Esc",
        57: "Caps Lock",
        64: "F17",
        65: ".",
        67: "*",
        69: "+",
        71: "Clear",
        75: "/",
        76: "Enter",
        78: "-",
        79: "F18",
        80: "F19",
        81: "=",
        82: "0",
        83: "1",
        84: "2",
        85: "3",
        86: "4",
        87: "5",
        88: "6",
        89: "7",
        90: "F20",
        91: "8",
        92: "9",
        93: "Yen",
        94: "JIS _",
        95: ",",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]

    static func comboLabel(keyCode: Int, modifierMask: Int) -> String {
        var prefix = ""
        if (modifierMask & ModifierMask.control) != 0 {
            prefix += "⌃"
        }
        if (modifierMask & ModifierMask.option) != 0 {
            prefix += "⌥"
        }
        if (modifierMask & ModifierMask.shift) != 0 {
            prefix += "⇧"
        }
        if (modifierMask & ModifierMask.command) != 0 {
            prefix += "⌘"
        }
        return prefix + keyName(for: keyCode)
    }

    static func keyName(for keyCode: Int) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
