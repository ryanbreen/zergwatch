import Foundation

struct HourBucket: Codable, Equatable {
    var apmActions: Int = 0
    var hotkeyChords: Int = 0
}

struct AppStats: Codable, Equatable {
    var actions: Int = 0
    var hotkeys: Int = 0
}

struct DayStats: Codable, Equatable {
    var date: String
    var hourly: [HourBucket]
    var perApp: [String: AppStats]
    var topCombos: [String: Int]
    var peak60APM: Int

    init(date: String) {
        self.date = date
        self.hourly = Array(repeating: HourBucket(), count: 24)
        self.perApp = [:]
        self.topCombos = [:]
        self.peak60APM = 0
    }

    var normalized: DayStats {
        var copy = self
        if copy.hourly.count < 24 {
            copy.hourly.append(contentsOf: Array(repeating: HourBucket(), count: 24 - copy.hourly.count))
        } else if copy.hourly.count > 24 {
            copy.hourly = Array(copy.hourly.prefix(24))
        }
        return copy
    }

    var totalActions: Int {
        hourly.reduce(0) { $0 + $1.apmActions }
    }

    var totalHotkeys: Int {
        hourly.reduce(0) { $0 + $1.hotkeyChords }
    }
}

enum CapturedInputEvent: Sendable {
    case keyDown(keyCode: Int, modifierMask: Int)
    case mouseDown

    var isHotkeyChord: Bool {
        switch self {
        case let .keyDown(_, modifierMask):
            ModifierMask.containsHotkeyModifier(modifierMask)
        case .mouseDown:
            false
        }
    }
}

enum ModifierMask {
    static let command = 1 << 0
    static let option = 1 << 1
    static let control = 1 << 2
    static let shift = 1 << 3

    static func containsHotkeyModifier(_ mask: Int) -> Bool {
        (mask & (command | option | control)) != 0
    }
}

struct ComboDisplay: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
}

struct AppDisplay: Identifiable, Equatable {
    let id: String
    let name: String
    let actions: Int
    let hotkeys: Int
}

struct HourChartPoint: Identifiable, Equatable {
    let hour: Int
    let metric: String
    let value: Int

    var id: String {
        "\(hour)-\(metric)"
    }
}

enum ChartMetricMode: String, CaseIterable, Identifiable {
    case both = "Both"
    case actions = "Actions"
    case hotkeys = "Hotkeys"

    var id: String {
        rawValue
    }
}

enum ComboIdentifier {
    static func make(keyCode: Int, modifierMask: Int) -> String {
        "\(keyCode):\(modifierMask)"
    }

    static func parse(_ rawValue: String) -> (keyCode: Int, modifierMask: Int)? {
        let parts = rawValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let keyCode = Int(parts[0]),
              let modifierMask = Int(parts[1])
        else {
            return nil
        }
        return (keyCode, modifierMask)
    }
}
