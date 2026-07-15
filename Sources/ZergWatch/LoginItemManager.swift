import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager {
    var isSMAppServiceFeasible: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var isEnabled: Bool {
        guard isSMAppServiceFeasible else {
            return false
        }

        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    func toggle() throws {
        guard isSMAppServiceFeasible else {
            throw LoginItemError.requiresLaunchAgent
        }

        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } else {
            throw LoginItemError.requiresLaunchAgent
        }
    }
}

enum LoginItemError: LocalizedError {
    case requiresLaunchAgent

    var errorDescription: String? {
        switch self {
        case .requiresLaunchAgent:
            "This standalone executable should be launched at login with the LaunchAgent in packaging/com.wrb.apmmeter.plist."
        }
    }
}
