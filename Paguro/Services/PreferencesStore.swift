import Foundation
import SwiftData
import PaguroCore

/// Owns the single live preferences row and its typed persistence API.
///
/// Callers read resolved values from this store. They cannot mutate the
/// SwiftData model directly. Runtime controllers apply side effects only after
/// a setter reports that the preference was saved.
@MainActor
final class PreferencesStore {
    private let context: ModelContext
    private let preferences: AppPreferences

    init(context: ModelContext) {
        self.context = context

        let loadedPreferences: AppPreferences?
        do {
            loadedPreferences = try context.fetch(FetchDescriptor<AppPreferences>()).first
        } catch {
            AppLogger.dataStore.error(
                "Failed to load preferences: \(error.localizedDescription)"
            )
            loadedPreferences = nil
        }

        if let loadedPreferences {
            preferences = loadedPreferences
        } else {
            let preferences = AppPreferences()
            context.insert(preferences)
            self.preferences = preferences
        }
    }

    var appPresenceMode: AppPresenceMode { preferences.appPresenceMode }
    var showBadgeCountInDock: Bool { preferences.showBadgeCountInDock }
    var autoDismissCookieBanners: Bool { preferences.autoDismissCookieBanners }
    var selectedSpaceID: UUID? { preferences.selectedSpaceID }
    var selectedServiceID: UUID? { preferences.selectedServiceID }
    var defaultZoom: Double { preferences.defaultZoomEffective }
    var scheduledDNDEnabled: Bool { preferences.scheduledDNDEnabled ?? false }
    var dndStartMinutes: Int { preferences.dndStartMinutes ?? (22 * 60) }
    var dndEndMinutes: Int { preferences.dndEndMinutes ?? (7 * 60) }
    var appLockEnabled: Bool { preferences.appLockEnabled ?? false }
    var lockOnLaunch: Bool { preferences.lockOnLaunch ?? true }
    var lockOnSleep: Bool { preferences.lockOnSleep ?? true }
    var railLayout: RailLayout { preferences.railLayout }
    var appearanceMode: AppearanceMode { preferences.appearanceMode }
    var contentBlockingEnabled: Bool { preferences.contentBlockingEnabledEffective }
    var annoyanceBlockingEnabled: Bool { preferences.annoyanceBlockingEnabledEffective }
    var googleFaviconFallbackEnabled: Bool {
        preferences.googleFaviconFallbackEnabledEffective
    }
    var autoHibernateIdleEnabled: Bool { preferences.autoHibernateIdleEnabledEffective }
    var autoHibernateIdleMinutes: Int { preferences.autoHibernateIdleMinutesEffective }
    var defaultCameraPolicy: MediaPermissionPolicy {
        preferences.defaultCameraPolicyRaw.flatMap(MediaPermissionPolicy.init(rawValue:)) ?? .ask
    }
    var defaultMicrophonePolicy: MediaPermissionPolicy {
        preferences.defaultMicrophonePolicyRaw.flatMap(MediaPermissionPolicy.init(rawValue:)) ?? .ask
    }

    func setAppPresenceMode(_ mode: AppPresenceMode) -> Bool {
        set(mode, at: \AppPreferences.appPresenceMode, reason: "app presence mode")
    }

    func setShowBadgeCountInDock(_ enabled: Bool) -> Bool {
        set(enabled, at: \AppPreferences.showBadgeCountInDock, reason: "Dock badge count")
    }

    func setAutoDismissCookieBanners(_ enabled: Bool) -> Bool {
        set(enabled, at: \AppPreferences.autoDismissCookieBanners, reason: "cookie banners")
    }

    func setWindowSelection(spaceID: UUID?, serviceID: UUID?) -> Bool {
        let oldSpaceID = preferences.selectedSpaceID
        let oldServiceID = preferences.selectedServiceID
        return commit(
            reason: "window selection",
            change: {
                self.preferences.selectedSpaceID = spaceID
                self.preferences.selectedServiceID = serviceID
            },
            restore: {
                self.preferences.selectedSpaceID = oldSpaceID
                self.preferences.selectedServiceID = oldServiceID
            }
        )
    }

    func setDefaultZoom(_ zoom: Double) -> Bool {
        set(Optional(zoom), at: \AppPreferences.defaultZoom, reason: "default zoom")
    }

    func setQuietHours(enabled: Bool, startMinutes: Int, endMinutes: Int) -> Bool {
        let oldEnabled = preferences.scheduledDNDEnabled
        let oldStart = preferences.dndStartMinutes
        let oldEnd = preferences.dndEndMinutes
        return commit(
            reason: "quiet hours",
            change: {
                self.preferences.scheduledDNDEnabled = enabled
                self.preferences.dndStartMinutes = startMinutes
                self.preferences.dndEndMinutes = endMinutes
            },
            restore: {
                self.preferences.scheduledDNDEnabled = oldEnabled
                self.preferences.dndStartMinutes = oldStart
                self.preferences.dndEndMinutes = oldEnd
            }
        )
    }

    func setAppLockEnabled(_ enabled: Bool) -> Bool {
        set(Optional(enabled), at: \AppPreferences.appLockEnabled, reason: "app lock")
    }

    func setLockOnLaunch(_ enabled: Bool) -> Bool {
        set(Optional(enabled), at: \AppPreferences.lockOnLaunch, reason: "lock on launch")
    }

    func setLockOnSleep(_ enabled: Bool) -> Bool {
        set(Optional(enabled), at: \AppPreferences.lockOnSleep, reason: "lock on sleep")
    }

    func setRailLayout(_ layout: RailLayout) -> Bool {
        set(Optional(layout.rawValue), at: \AppPreferences.railLayoutRaw, reason: "rail layout")
    }

    func setAppearanceMode(_ mode: AppearanceMode) -> Bool {
        set(Optional(mode.rawValue), at: \AppPreferences.appearanceModeRaw, reason: "appearance")
    }

    func setContentBlockingEnabled(_ enabled: Bool) -> Bool {
        set(Optional(enabled), at: \AppPreferences.contentBlockingEnabled, reason: "content blocking")
    }

    func setAnnoyanceBlockingEnabled(_ enabled: Bool) -> Bool {
        set(Optional(enabled), at: \AppPreferences.annoyanceBlockingEnabled, reason: "annoyance blocking")
    }

    func setDefaultMediaPolicies(
        camera: MediaPermissionPolicy,
        microphone: MediaPermissionPolicy
    ) -> Bool {
        let oldCamera = preferences.defaultCameraPolicyRaw
        let oldMicrophone = preferences.defaultMicrophonePolicyRaw
        return commit(
            reason: "default media policies",
            change: {
                self.preferences.defaultCameraPolicyRaw = camera.rawValue
                self.preferences.defaultMicrophonePolicyRaw = microphone.rawValue
            },
            restore: {
                self.preferences.defaultCameraPolicyRaw = oldCamera
                self.preferences.defaultMicrophonePolicyRaw = oldMicrophone
            }
        )
    }

    func setGoogleFaviconFallbackEnabled(_ enabled: Bool) -> Bool {
        set(
            Optional(enabled),
            at: \AppPreferences.googleFaviconFallbackEnabled,
            reason: "Google favicon fallback"
        )
    }

    func setAutoHibernateIdleEnabled(_ enabled: Bool) -> Bool {
        set(Optional(enabled), at: \AppPreferences.autoHibernateIdleEnabled, reason: "auto-hibernation")
    }

    func setAutoHibernateIdleMinutes(_ minutes: Int) -> Bool {
        let resolvedMinutes = min(120, max(1, minutes))
        return set(
            Optional(resolvedMinutes),
            at: \AppPreferences.autoHibernateIdleMinutes,
            reason: "auto-hibernation interval"
        )
    }

    func configurationPreferences() -> ConfigurationPreferences {
        var result = ConfigurationPreferences()
        result.appPresenceMode = appPresenceMode.rawValue
        result.showBadgeCountInDock = showBadgeCountInDock
        result.autoDismissCookieBanners = autoDismissCookieBanners
        result.defaultZoom = defaultZoom
        result.scheduledDNDEnabled = scheduledDNDEnabled
        result.dndStartMinutes = dndStartMinutes
        result.dndEndMinutes = dndEndMinutes
        result.appLockEnabled = appLockEnabled
        result.lockOnLaunch = lockOnLaunch
        result.lockOnSleep = lockOnSleep
        result.railLayout = railLayout.rawValue
        result.appearanceMode = appearanceMode.rawValue
        result.contentBlockingEnabled = contentBlockingEnabled
        result.annoyanceBlockingEnabled = annoyanceBlockingEnabled
        result.defaultCameraPolicy = defaultCameraPolicy.rawValue
        result.defaultMicrophonePolicy = defaultMicrophonePolicy.rawValue
        result.googleFaviconFallbackEnabled = googleFaviconFallbackEnabled
        result.autoHibernateIdleEnabled = autoHibernateIdleEnabled
        result.autoHibernateIdleMinutes = autoHibernateIdleMinutes
        return result
    }

    /// Stages preferences in the workspace import transaction; the caller saves once.
    func stageConfiguration(_ value: ConfigurationPreferences) {
        preferences.appPresenceMode = AppPresenceMode(rawValue: value.appPresenceMode) ?? .both
        preferences.showBadgeCountInDock = value.showBadgeCountInDock
        preferences.autoDismissCookieBanners = value.autoDismissCookieBanners
        preferences.defaultZoom = value.defaultZoom
        preferences.scheduledDNDEnabled = value.scheduledDNDEnabled
        preferences.dndStartMinutes = value.dndStartMinutes
        preferences.dndEndMinutes = value.dndEndMinutes
        preferences.appLockEnabled = value.appLockEnabled
        preferences.lockOnLaunch = value.lockOnLaunch
        preferences.lockOnSleep = value.lockOnSleep
        preferences.railLayoutRaw = value.railLayout
        preferences.appearanceModeRaw = value.appearanceMode
        preferences.contentBlockingEnabled = value.contentBlockingEnabled
        preferences.annoyanceBlockingEnabled = value.annoyanceBlockingEnabled
        preferences.defaultCameraPolicyRaw = value.defaultCameraPolicy
        preferences.defaultMicrophonePolicyRaw = value.defaultMicrophonePolicy
        preferences.googleFaviconFallbackEnabled = value.googleFaviconFallbackEnabled
        preferences.autoHibernateIdleEnabled = value.autoHibernateIdleEnabled
        preferences.autoHibernateIdleMinutes = value.autoHibernateIdleMinutes
    }

    private func set<Value>(
        _ value: Value,
        at keyPath: ReferenceWritableKeyPath<AppPreferences, Value>,
        reason: String
    ) -> Bool {
        let oldValue = preferences[keyPath: keyPath]
        return commit(
            reason: reason,
            change: { self.preferences[keyPath: keyPath] = value },
            restore: { self.preferences[keyPath: keyPath] = oldValue }
        )
    }

    private func commit(
        reason: String,
        change: () -> Void,
        restore: () -> Void
    ) -> Bool {
        if preferences.modelContext == nil {
            context.insert(preferences)
        }
        change()
        guard context.saveOrRollback(reason: "save preference (\(reason))") else {
            // `rollback()` restores an existing attached row. A row that had
            // not been saved yet is detached instead, so restore only that
            // object for accurate reads before the next insertion attempt.
            if preferences.modelContext == nil {
                restore()
            }
            return false
        }
        return true
    }
}
