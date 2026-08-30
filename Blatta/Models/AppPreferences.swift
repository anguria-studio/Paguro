import Foundation
import SwiftData

enum AppPresenceMode: String, Codable {
    case dock
    case menuBar
    case both

    /// The Dock icon stays visible while a main window is closed.
    var showsDockIcon: Bool { self != .menuBar }

    /// The menu-bar item is present.
    var showsMenuBarItem: Bool { self != .dock }
}

/// Where the workspaces and the services sit around the web content.
///
/// Two layouts give one rail both: down the left, or along the top. Two give
/// each its own: the workspaces down the left with the services along the top,
/// or the reverse. `hybrid` is retired and its users are mapped onto
/// `workspacesLeft`, the layout it named — see `resolving(_:)`, which is the
/// only correct way to read a stored value.
enum RailLayout: String, Codable, CaseIterable {
    /// One rail down the left (the default).
    case sidebar
    /// One rail along the top, as a bar of tabs.
    case topBars
    /// The workspaces down the left, the services along the top.
    case workspacesLeft
    /// The services down the left, the workspaces along the top.
    case servicesLeft

    var displayName: String {
        switch self {
        case .sidebar: return "Rail on the left"
        case .topBars: return "Bar along the top"
        case .workspacesLeft: return "Workspaces left, services on top"
        case .servicesLeft: return "Services left, workspaces on top"
        }
    }

    /// The layout gives the workspaces a rail of their own.
    var showsBothRails: Bool {
        switch self {
        case .sidebar, .topBars: return false
        case .workspacesLeft, .servicesLeft: return true
        }
    }

    /// The services live in the bar along the top.
    var servicesInBar: Bool {
        switch self {
        case .topBars, .workspacesLeft: return true
        case .sidebar, .servicesLeft: return false
        }
    }

    /// The layout has a rail down the left, which can collapse to icons.
    var hasSideRail: Bool {
        self != .topBars
    }

    /// The raw value of the retired case. It named the layout with the
    /// workspaces on the left and the services on top, which is back.
    static let retiredHybridRawValue = "hybrid"

    /// Reads a stored raw value, mapping the retired `hybrid` forward.
    ///
    /// The forward-map has to be explicit. A plain
    /// `RailLayout(rawValue:) ?? .sidebar` would send every `hybrid` user to
    /// the sidebar, which is the layout furthest from the one they picked.
    static func resolving(_ raw: String?) -> RailLayout {
        guard let raw else { return .sidebar }
        if let known = RailLayout(rawValue: raw) { return known }
        if raw == retiredHybridRawValue { return .workspacesLeft }
        return .sidebar
    }
}

/// App-level light/dark appearance override.
enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Always Light"
        case .dark: return "Always Dark"
        }
    }
}

enum AppPreferenceDefaults {
    static let appPresenceMode = AppPresenceMode.both
    static let showBadgeCountInDock = true
    static let autoDismissCookieBanners = false
}

@Model
final class AppPreferences {
    @Attribute(.unique) var id: UUID
    var appPresenceMode: AppPresenceMode

    /// Retired compatibility field. Launch-at-login state now comes from
    /// `SMAppService`; keep this property so existing stores retain their schema.
    var launchAtLogin: Bool

    /// Retired compatibility field. Blatta's current commands are always active;
    /// keep this property so existing stores retain their schema.
    var globalKeyboardShortcutsEnabled: Bool
    var showBadgeCountInDock: Bool
    var autoDismissCookieBanners: Bool
    var selectedSpaceID: UUID?
    var selectedServiceID: UUID?

    /// Blatta-wide default page zoom applied to services that have no explicit
    /// per-service zoom. Optional so SwiftData lightweight migration succeeds on
    /// existing rows; nil is treated as 1.0. Read via `defaultZoomEffective`.
    var defaultZoom: Double?

    /// Scheduled "quiet hours" Do Not Disturb. All optional for SwiftData
    /// lightweight migration. Start/end are minutes since midnight; nil defaults
    /// to 22:00–07:00 when the schedule is first enabled.
    var scheduledDNDEnabled: Bool?
    var dndStartMinutes: Int?
    var dndEndMinutes: Int?

    /// App lock (Touch ID / password). Optional for SwiftData lightweight
    /// migration. `lockOnLaunch`/`lockOnSleep` default true once the lock is
    /// enabled; the user chooses which triggers apply in Settings.
    var appLockEnabled: Bool?
    var lockOnLaunch: Bool?
    var lockOnSleep: Bool?

    /// Rail layout. Optional so SwiftData lightweight migration succeeds on
    /// existing rows; nil or an unknown value resolves to `.sidebar`. Read via
    /// `railLayout`.
    var railLayoutRaw: String?

    /// App-level appearance override. Optional for lightweight migration; nil or
    /// unknown resolves to `.system`. Read via `appearanceMode`.
    var appearanceModeRaw: String?

    /// Global on/off for the network content blocker. Optional for SwiftData
    /// lightweight migration; nil is treated as enabled (`contentBlockingEnabledEffective`),
    /// so both fresh installs and existing installs upgrading into the feature
    /// get blocking on by default.
    var contentBlockingEnabled: Bool?

    /// "Hide annoyances" (cookie notices, newsletter pop-ups, floating bars) on
    /// top of ad/tracker blocking. Optional for SwiftData lightweight migration;
    /// nil is treated as off — it's opt-in because cosmetic hiding is more
    /// aggressive than domain blocking.
    var annoyanceBlockingEnabled: Bool?

    /// Default camera / microphone permission for services that haven't pinned
    /// their own. Stored raw for SwiftData lightweight migration; nil resolves to
    /// `.ask` (see `MediaPermissionResolver.effectivePolicy`).
    var defaultCameraPolicyRaw: String?
    var defaultMicrophonePolicyRaw: String?

    /// Allow the Google favicon service as a last-resort icon source. Optional
    /// for SwiftData lightweight migration; nil is treated as off — it's opt-in
    /// because the request discloses the service's hostname to a third party,
    /// and a custom service's host can be private. Off just means a service
    /// whose own host serves no usable icon falls back to its monogram.
    var googleFaviconFallbackEnabled: Bool?
    /// Fully hibernate a background service after it has been idle for
    /// `autoHibernateIdleMinutes`, freeing its WebContent process. Optional for
    /// SwiftData lightweight migration; nil is treated as off — opt-in because it
    /// changes runtime behaviour. Notification-critical services (the Messaging
    /// catalog category) and any service marked "Keep Loaded" are never touched,
    /// so real-time alerts for chat apps are preserved; a hibernated service still
    /// refreshes its unread badge on a periodic background sweep (every few
    /// minutes), and that count only climbs until the service is reopened.
    var autoHibernateIdleEnabled: Bool?

    /// Idle minutes before auto-hibernation kicks in. Optional; nil resolves to 10.
    var autoHibernateIdleMinutes: Int?

    init(
        id: UUID = UUID(),
        appPresenceMode: AppPresenceMode = AppPreferenceDefaults.appPresenceMode,
        launchAtLogin: Bool = false,
        globalKeyboardShortcutsEnabled: Bool = true,
        showBadgeCountInDock: Bool = AppPreferenceDefaults.showBadgeCountInDock,
        autoDismissCookieBanners: Bool = AppPreferenceDefaults.autoDismissCookieBanners,
        selectedSpaceID: UUID? = nil,
        selectedServiceID: UUID? = nil,
        defaultZoom: Double? = nil,
        scheduledDNDEnabled: Bool? = nil,
        dndStartMinutes: Int? = nil,
        dndEndMinutes: Int? = nil,
        appLockEnabled: Bool? = nil,
        lockOnLaunch: Bool? = nil,
        lockOnSleep: Bool? = nil,
        railLayoutRaw: String? = nil,
        appearanceModeRaw: String? = nil,
        contentBlockingEnabled: Bool? = nil,
        annoyanceBlockingEnabled: Bool? = nil,
        defaultCameraPolicyRaw: String? = nil,
        defaultMicrophonePolicyRaw: String? = nil,
        googleFaviconFallbackEnabled: Bool? = nil,
        autoHibernateIdleEnabled: Bool? = nil,
        autoHibernateIdleMinutes: Int? = nil
    ) {
        self.id = id
        self.appPresenceMode = appPresenceMode
        self.launchAtLogin = launchAtLogin
        self.globalKeyboardShortcutsEnabled = globalKeyboardShortcutsEnabled
        self.showBadgeCountInDock = showBadgeCountInDock
        self.autoDismissCookieBanners = autoDismissCookieBanners
        self.selectedSpaceID = selectedSpaceID
        self.selectedServiceID = selectedServiceID
        self.defaultZoom = defaultZoom
        self.scheduledDNDEnabled = scheduledDNDEnabled
        self.dndStartMinutes = dndStartMinutes
        self.dndEndMinutes = dndEndMinutes
        self.appLockEnabled = appLockEnabled
        self.lockOnLaunch = lockOnLaunch
        self.lockOnSleep = lockOnSleep
        self.railLayoutRaw = railLayoutRaw
        self.appearanceModeRaw = appearanceModeRaw
        self.contentBlockingEnabled = contentBlockingEnabled
        self.annoyanceBlockingEnabled = annoyanceBlockingEnabled
        self.defaultCameraPolicyRaw = defaultCameraPolicyRaw
        self.defaultMicrophonePolicyRaw = defaultMicrophonePolicyRaw
        self.googleFaviconFallbackEnabled = googleFaviconFallbackEnabled
        self.autoHibernateIdleEnabled = autoHibernateIdleEnabled
        self.autoHibernateIdleMinutes = autoHibernateIdleMinutes
    }

    /// Materialises the storage-optional default zoom (nil → 1.0).
    var defaultZoomEffective: Double { defaultZoom ?? 1.0 }

    /// Resolves the stored rail layout. `hybrid` maps onto `.topBars`; anything
    /// else unknown falls back to `.sidebar`. See `RailLayout.resolving(_:)`.
    var railLayout: RailLayout {
        RailLayout.resolving(railLayoutRaw)
    }

    /// Resolves the stored appearance override, defaulting to `.system`.
    var appearanceMode: AppearanceMode {
        appearanceModeRaw.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    /// Materialises the storage-optional content-blocking flag (nil → true).
    var contentBlockingEnabledEffective: Bool { contentBlockingEnabled ?? true }

    /// Materialises the storage-optional annoyance-blocking flag (nil → false).
    var annoyanceBlockingEnabledEffective: Bool { annoyanceBlockingEnabled ?? false }

    /// Materialises the storage-optional Google favicon fallback flag (nil → false).
    var googleFaviconFallbackEnabledEffective: Bool { googleFaviconFallbackEnabled ?? false }
    /// Materialises the storage-optional auto-hibernate flag (nil → false).
    var autoHibernateIdleEnabledEffective: Bool { autoHibernateIdleEnabled ?? false }

    /// Idle minutes before auto-hibernation, clamped to a sane 1...120 (nil → 10).
    var autoHibernateIdleMinutesEffective: Int {
        min(120, max(1, autoHibernateIdleMinutes ?? 10))
    }
}
