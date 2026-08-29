import AppKit
import Observation
import ServiceManagement
import os

/// Applies the presence preference: which of the Dock icon and the menu-bar
/// item Blatta shows, and whether Blatta starts at login.
///
/// `mode` is observable so the SwiftUI scene can insert or remove the
/// `MenuBarExtra` when the preference changes.
@MainActor
@Observable
final class AppPresenceController {
    private static let logger = Logger(subsystem: "com.tommasolaterza.Blatta", category: "AppPresence")
    @ObservationIgnored private weak var appDelegate: AppDelegate?
    private(set) var mode = AppPreferenceDefaults.appPresenceMode

    func connect(to appDelegate: AppDelegate, initialMode: AppPresenceMode) {
        self.appDelegate = appDelegate
        setMode(initialMode)
    }

    func setMode(_ mode: AppPresenceMode) {
        self.mode = mode
        appDelegate?.alwaysShowDockIcon = mode.showsDockIcon
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Launch at login error: \(error.localizedDescription)")
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
