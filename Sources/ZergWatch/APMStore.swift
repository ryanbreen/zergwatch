import Combine
import Foundation

struct RecentActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case chord
        case key
        case click
    }

    let id: Int
    let label: String
    let kind: Kind
    let at: Date
}

@MainActor
final class APMStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var day: DayStats
    @Published private(set) var liveAPM: Int = 0
    @Published private(set) var accessibilityTrusted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false
    @Published private(set) var eventTapActive: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var lastPersistenceError: String?

    let applicationSupportDirectory: URL

    private let fileManager: FileManager
    private var currentAppName: String = "Unknown"
    private var actionTimestamps: [TimeInterval] = []

    private static let recentActivityCap = 40
    // In-memory only ring buffer of recent captured events (newest last here,
    // exposed newest-first via recentActivity()). NOT persisted to disk —
    // must never be added to DayStats / the Codable day model.
    private var recentEvents: [RecentActivity] = []
    private var recentEventCounter = 0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        self.applicationSupportDirectory = baseDirectory.appendingPathComponent("ZergWatch", isDirectory: true)
        self.day = DayStats(date: Self.localDayString(for: Date()))
        createApplicationSupportDirectory()
        loadToday()
    }

    var totalActions: Int {
        day.totalActions
    }

    var totalHotkeys: Int {
        day.totalHotkeys
    }

    var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    var trackingReady: Bool {
        accessibilityTrusted && inputMonitoringGranted
    }

    var displayDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar.current
        inputFormatter.locale = Locale.current
        inputFormatter.timeZone = TimeZone.current
        inputFormatter.dateFormat = "yyyy-MM-dd"

        let outputFormatter = DateFormatter()
        outputFormatter.calendar = Calendar.current
        outputFormatter.locale = Locale.current
        outputFormatter.timeZone = TimeZone.current
        outputFormatter.dateStyle = .full
        outputFormatter.timeStyle = .none

        guard let date = inputFormatter.date(from: day.date) else {
            return day.date
        }
        return outputFormatter.string(from: date)
    }

    var playstyleFlavor: String {
        switch day.peak60APM {
        case ..<60:
            "Bronze macro, calm hands"
        case 60..<120:
            "Diamond micro, clean control"
        case 120..<200:
            "Grandmaster tempo"
        default:
            "Pro-gamer Zerg storm"
        }
    }

    func loadToday() {
        let today = Self.localDayString(for: Date())
        let url = fileURL(for: today)
        guard fileManager.fileExists(atPath: url.path) else {
            day = DayStats(date: today)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            day = try JSONDecoder().decode(DayStats.self, from: data).normalized
            lastPersistenceError = nil
        } catch {
            day = DayStats(date: today)
            lastPersistenceError = error.localizedDescription
        }
    }

    func save() {
        createApplicationSupportDirectory()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(day.normalized)
            try data.write(to: fileURL(for: day.date), options: .atomic)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    func resetToday() {
        day = DayStats(date: Self.localDayString(for: Date()))
        actionTimestamps.removeAll(keepingCapacity: true)
        liveAPM = 0
        save()
    }

    func rollToCurrentDayIfNeeded(now: Date = Date()) {
        let today = Self.localDayString(for: now)
        guard day.date != today else {
            return
        }
        save()
        day = DayStats(date: today)
        actionTimestamps.removeAll(keepingCapacity: true)
        liveAPM = 0
        save()
    }

    func record(_ input: CapturedInputEvent, now: Date = Date()) {
        guard !isPaused else {
            refreshLiveAPM(now: now)
            return
        }

        rollToCurrentDayIfNeeded(now: now)

        let hour = Calendar.current.component(.hour, from: now)
        guard day.hourly.indices.contains(hour) else {
            return
        }

        let isHotkey = input.isHotkeyChord
        objectWillChange.send()
        day.hourly[hour].apmActions += 1
        if isHotkey {
            day.hourly[hour].hotkeyChords += 1
        }

        var appStats = day.perApp[currentAppName, default: AppStats()]
        appStats.actions += 1
        if isHotkey {
            appStats.hotkeys += 1
        }
        day.perApp[currentAppName] = appStats

        if case let .keyDown(keyCode, modifierMask) = input, isHotkey, keyCode >= 0 {
            let key = ComboIdentifier.make(keyCode: keyCode, modifierMask: modifierMask)
            day.topCombos[key, default: 0] += 1
        }

        appendRecentActivity(for: input, now: now)

        actionTimestamps.append(now.timeIntervalSinceReferenceDate)
        updateLiveAPM(now: now)
        if liveAPM > day.peak60APM {
            objectWillChange.send()
            day.peak60APM = liveAPM
        }
    }

    func refreshLiveAPM(now: Date = Date()) {
        rollToCurrentDayIfNeeded(now: now)
        updateLiveAPM(now: now)
    }

    func setAccessibilityTrusted(_ trusted: Bool) {
        guard accessibilityTrusted != trusted else {
            return
        }
        accessibilityTrusted = trusted
    }

    func setInputMonitoringGranted(_ granted: Bool) {
        guard inputMonitoringGranted != granted else {
            return
        }
        inputMonitoringGranted = granted
    }

    func setEventTapActive(_ active: Bool) {
        guard eventTapActive != active else {
            return
        }
        eventTapActive = active
    }

    func togglePaused() {
        isPaused.toggle()
        refreshLiveAPM()
    }

    func setFrontmostAppName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            currentAppName = "Unknown"
        } else {
            currentAppName = String(trimmed.prefix(80))
        }
    }

    func topCombos(limit: Int = 5) -> [ComboDisplay] {
        day.topCombos
            .compactMap { rawKey, count -> ComboDisplay? in
                guard let combo = ComboIdentifier.parse(rawKey) else {
                    return nil
                }
                return ComboDisplay(
                    id: rawKey,
                    label: KeyCodes.comboLabel(keyCode: combo.keyCode, modifierMask: combo.modifierMask),
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    lhs.label < rhs.label
                } else {
                    lhs.count > rhs.count
                }
            }
            .prefix(limit)
            .map { $0 }
    }

    func topApps(limit: Int = 5) -> [AppDisplay] {
        day.perApp
            .map { appName, stats in
                AppDisplay(id: appName, name: appName, actions: stats.actions, hotkeys: stats.hotkeys)
            }
            .sorted { lhs, rhs in
                if lhs.actions == rhs.actions {
                    lhs.name < rhs.name
                } else {
                    lhs.actions > rhs.actions
                }
            }
            .prefix(limit)
            .map { $0 }
    }

    func chartPoints(mode: ChartMetricMode) -> [HourChartPoint] {
        day.hourly.enumerated().flatMap { hour, bucket in
            switch mode {
            case .both:
                [
                    HourChartPoint(hour: hour, metric: "Actions", value: bucket.apmActions),
                    HourChartPoint(hour: hour, metric: "Hotkeys", value: bucket.hotkeyChords)
                ]
            case .actions:
                [HourChartPoint(hour: hour, metric: "Actions", value: bucket.apmActions)]
            case .hotkeys:
                [HourChartPoint(hour: hour, metric: "Hotkeys", value: bucket.hotkeyChords)]
            }
        }
    }

    func fileURL(for dayString: String) -> URL {
        applicationSupportDirectory.appendingPathComponent("\(dayString).json", isDirectory: false)
    }

    /// Newest-first snapshot of the in-memory recent activity ring buffer.
    /// Labels are privacy-clean: never a captured character, only "key"/"click"/a chord combo.
    func recentActivity() -> [RecentActivity] {
        recentEvents.reversed()
    }

    private func appendRecentActivity(for input: CapturedInputEvent, now: Date) {
        let label: String
        let kind: RecentActivity.Kind
        switch input {
        case let .keyDown(keyCode, modifierMask):
            if input.isHotkeyChord {
                label = KeyCodes.comboLabel(keyCode: keyCode, modifierMask: modifierMask)
                kind = .chord
            } else {
                // PRIVACY: never the actual character/letter — just the word "key".
                label = "key"
                kind = .key
            }
        case .mouseDown:
            label = "click"
            kind = .click
        }

        recentEventCounter += 1
        recentEvents.append(RecentActivity(id: recentEventCounter, label: label, kind: kind, at: now))
        if recentEvents.count > Self.recentActivityCap {
            recentEvents.removeFirst(recentEvents.count - Self.recentActivityCap)
        }
    }

    private func updateLiveAPM(now: Date) {
        pruneTimestamps(now: now)
        let cutoff = now.timeIntervalSinceReferenceDate - 60
        liveAPM = actionTimestamps.filter { $0 >= cutoff }.count
    }

    private func pruneTimestamps(now: Date) {
        let cutoff = now.timeIntervalSinceReferenceDate - 120
        guard let firstKeptIndex = actionTimestamps.firstIndex(where: { $0 >= cutoff }) else {
            actionTimestamps.removeAll(keepingCapacity: true)
            return
        }
        if firstKeptIndex > 0 {
            actionTimestamps.removeSubrange(0..<firstKeptIndex)
        }
    }

    private func createApplicationSupportDirectory() {
        do {
            try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private static func localDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
