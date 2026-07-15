import AppKit
import SwiftUI

@MainActor
protocol StatusControllerDelegate: AnyObject {
    func openAccessibilitySettings()
    func openInputMonitoringSettings()
    func openDataFolder()
    func resetTodayWithConfirmation()
    func togglePause()
    func quit()
    func toggleLaunchAtLogin()
}

@MainActor
final class StatusController: NSObject {
    private let store: APMStore
    private let loginItemManager: LoginItemManager
    private weak var delegate: StatusControllerDelegate?
    private let statusItem: NSStatusItem
    private var dashboardWindow: NSWindow?

    init(store: APMStore, loginItemManager: LoginItemManager, delegate: StatusControllerDelegate) {
        self.store = store
        self.loginItemManager = loginItemManager
        self.delegate = delegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configureDashboardWindow()
        refreshTitle()
    }

    func refreshTitle() {
        guard let button = statusItem.button else {
            return
        }

        if !store.accessibilityTrusted {
            button.title = "⚡ Needs Access"
            button.toolTip = "Zerg Watch needs Accessibility permission"
        } else if !store.inputMonitoringGranted {
            button.title = "⚡ Needs Input"
            button.toolTip = "Zerg Watch needs Input Monitoring permission"
        } else if store.isPaused {
            button.title = "⚡ Paused"
            button.toolTip = "Zerg Watch is paused"
        } else {
            button.title = "⚡ \(store.liveAPM)"
            button.toolTip = "Live actions per minute"
        }
    }

    func showMenu() {
        guard let button = statusItem.button else {
            return
        }

        let menu = NSMenu()
        menu.addItem(menuItem(
            title: store.isPaused ? "Resume Tracking" : "Pause Tracking",
            action: #selector(togglePause)
        ))
        menu.addItem(menuItem(title: "Open Data Folder", action: #selector(openDataFolder)))
        menu.addItem(menuItem(title: "Reset Today", action: #selector(resetToday)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        menu.addItem(menuItem(title: "Open Input Monitoring Settings", action: #selector(openInputMonitoringSettings)))

        let launchItem = menuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin))
        if loginItemManager.isSMAppServiceFeasible {
            launchItem.state = loginItemManager.isEnabled ? .on : .off
        } else {
            launchItem.title = "Launch at Login (LaunchAgent)"
            launchItem.action = #selector(showLaunchAgentHelp)
        }
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Quit Zerg Watch", action: #selector(quit)))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(statusButtonPressed)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private func configureDashboardWindow() {
        let actions = DashboardActions(
            openAccessibilitySettings: { [weak self] in self?.delegate?.openAccessibilitySettings() },
            openInputMonitoringSettings: { [weak self] in self?.delegate?.openInputMonitoringSettings() },
            openDataFolder: { [weak self] in self?.delegate?.openDataFolder() },
            resetToday: { [weak self] in self?.delegate?.resetTodayWithConfirmation() },
            togglePause: { [weak self] in self?.delegate?.togglePause() },
            showMenu: { [weak self] in self?.showMenu() },
            quit: { [weak self] in self?.delegate?.quit() }
        )

        let hostingController = NSHostingController(rootView: DashboardView(store: store, actions: actions))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zerg Watch"
        window.contentMinSize = NSSize(width: 380, height: 480)
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("ZergWatchDashboard")
        dashboardWindow = window
    }

    private func toggleDashboardWindow() {
        guard let window = dashboardWindow else {
            return
        }

        if window.isVisible && window.isKeyWindow {
            window.close()
        } else {
            refreshTitle()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func statusButtonPressed() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleDashboardWindow()
        }
    }

    @objc private func openAccessibilitySettings() {
        delegate?.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        delegate?.openInputMonitoringSettings()
    }

    @objc private func openDataFolder() {
        delegate?.openDataFolder()
    }

    @objc private func resetToday() {
        delegate?.resetTodayWithConfirmation()
    }

    @objc private func togglePause() {
        delegate?.togglePause()
        refreshTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        delegate?.toggleLaunchAtLogin()
    }

    @objc private func showLaunchAgentHelp() {
        let alert = NSAlert()
        alert.messageText = "Use the LaunchAgent template"
        alert.informativeText = "This standalone executable is not an app bundle, so SMAppService.mainApp is not available. Build the release binary, then install packaging/com.wrb.apmmeter.plist into ~/Library/LaunchAgents."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        delegate?.quit()
    }
}
