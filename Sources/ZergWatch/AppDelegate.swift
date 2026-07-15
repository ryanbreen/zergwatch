import AppKit
import Darwin
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, StatusControllerDelegate {
    private let store = APMStore()
    private let loginItemManager = LoginItemManager()
    private var eventMonitor: EventMonitor?
    private var statusController: StatusController?
    private var liveTimer: Timer?
    private var autosaveTimer: Timer?
    private var permissionPollTimer: Timer?
    private var midnightTimer: Timer?
    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        store.setFrontmostAppName(NSWorkspace.shared.frontmostApplication?.localizedName)
        observeFrontmostApplications()

        let statusController = StatusController(
            store: store,
            loginItemManager: loginItemManager,
            delegate: self
        )
        self.statusController = statusController

        startTimers()
        installSignalHandler()
        refreshPermissions(promptForAccessibility: true)
        AccessibilityPermission.requestInputMonitoring()
        refreshPermissions(promptForAccessibility: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        eventMonitor?.stop()
        invalidateTimers()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    func openInputMonitoringSettings() {
        AccessibilityPermission.openInputMonitoringSettings()
    }

    func openDataFolder() {
        do {
            try FileManager.default.createDirectory(
                at: store.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            showAlert(title: "Could not open data folder", message: error.localizedDescription)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([store.applicationSupportDirectory])
    }

    func resetTodayWithConfirmation() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset today's APM data?"
        alert.informativeText = "This clears today's local counters and rewrites today's JSON file."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        store.resetToday()
        statusController?.refreshTitle()
    }

    func togglePause() {
        store.togglePaused()
        statusController?.refreshTitle()
    }

    func quit() {
        store.save()
        NSApplication.shared.terminate(nil)
    }

    func toggleLaunchAtLogin() {
        do {
            try loginItemManager.toggle()
        } catch {
            showAlert(title: "Launch at Login", message: error.localizedDescription)
        }
    }

    private func startTimers() {
        let liveTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickLiveAPM()
            }
        }
        RunLoop.main.add(liveTimer, forMode: .common)
        self.liveTimer = liveTimer

        let autosaveTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.save()
            }
        }
        RunLoop.main.add(autosaveTimer, forMode: .common)
        self.autosaveTimer = autosaveTimer

        startPermissionPolling()
        scheduleMidnightTimer()
    }

    private func invalidateTimers() {
        liveTimer?.invalidate()
        autosaveTimer?.invalidate()
        permissionPollTimer?.invalidate()
        midnightTimer?.invalidate()
        terminationSource?.cancel()
    }

    private func tickLiveAPM() {
        store.refreshLiveAPM()
        statusController?.refreshTitle()
    }

    private func refreshPermissions(promptForAccessibility prompt: Bool) {
        let trusted = AccessibilityPermission.isTrusted(prompt: prompt)
        let inputMonitoringGranted = AccessibilityPermission.inputMonitoringGranted()
        store.setAccessibilityTrusted(trusted)
        store.setInputMonitoringGranted(inputMonitoringGranted)
        statusController?.refreshTitle()

        if store.trackingReady {
            installEventTapIfNeeded()
        } else {
            eventMonitor?.stop()
        }
    }

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions(promptForAccessibility: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func installEventTapIfNeeded() {
        if eventMonitor == nil {
            eventMonitor = EventMonitor(store: store)
        }
        let active = eventMonitor?.start() ?? false
        store.setEventTapActive(active)
    }

    private func observeFrontmostApplications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        store.setFrontmostAppName(application?.localizedName)
    }

    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()

        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        let nextMidnight = calendar.startOfDay(for: tomorrow).addingTimeInterval(1)
        let interval = max(1, nextMidnight.timeIntervalSince(now))

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.store.rollToCurrentDayIfNeeded()
                self?.statusController?.refreshTitle()
                self?.scheduleMidnightTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.store.save()
                NSApplication.shared.terminate(nil)
            }
        }
        source.resume()
        terminationSource = source
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
