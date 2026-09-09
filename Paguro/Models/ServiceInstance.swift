import Foundation
import SwiftData
import PaguroCore

@Model
final class ServiceInstance {
    @Attribute(.unique) var id: UUID
    var label: String
    var url: String
    var customIconData: Data?
    var fetchedIconData: Data?
    var faviconFetchedAt: Date?
    var catalogEntryID: String?
    var isMuted: Bool
    var showBadge: Bool
    var neverHibernate: Bool
    var userAgent: String?
    var dataStoreIdentifier: UUID
    /// Per-service page zoom (e.g. 1.0 = 100%, 1.25 = 125%). Stored optional
    /// so SwiftData lightweight migration succeeds on existing rows — read
    /// sites should use `zoomLevelEffective` which substitutes 1.0 for nil.
    var pageZoom: Double?

    /// Whether this service forwards its web notifications to macOS Notification
    /// Center. Stored optional so SwiftData lightweight migration succeeds on
    /// existing rows — nil is treated as enabled (the prior default). Read sites
    /// should use `notifiesOSEffective`. Independent of `showBadge` (badge) and
    /// of `isMuted` (mute is the master override over both).
    var osNotificationsEnabled: Bool?

    /// Per-service custom CSS injected into the page. Stored optional so
    /// SwiftData lightweight migration succeeds on existing rows — nil means
    /// "use the built-in default for this service" (see `ServiceCSSDefaults`),
    /// so a service like LinkedIn still gets its messaging-only view untouched.
    /// A non-nil value overrides the default; a blank value disables both.
    var customCSS: String?

    /// Legacy Dark Reader flag. Optional for SwiftData lightweight migration.
    /// New code reads it only when it resolves an old service appearance value.
    var forceDarkMode: Bool?

    /// Per-service web appearance, stored in the existing raw field so the
    /// SwiftData shape does not change. Read via `webAppearance`, which maps the
    /// old Dark Reader values. Only the new appearance values are written now.
    var darkModeRaw: String?

    /// Per-service camera / microphone permission, stored raw for SwiftData
    /// lightweight migration. nil means "no per-service value" — resolution falls
    /// back to the global default, then `.ask` (see `MediaPermissionResolver`).
    /// Read the raw directly for resolution; the `cameraPolicy`/`microphonePolicy`
    /// accessors are for the editor UI (nil → `.ask`).
    var cameraPolicyRaw: String?
    var microphonePolicyRaw: String?

    /// Open a link that leaves this service in an in-app Paguro window instead of
    /// the system browser. Only affects links that no other Paguro service owns —
    /// a link matching another service still switches to it. Optional for
    /// SwiftData lightweight migration; nil is treated as off (today's behaviour:
    /// external links open in the default browser). Read via
    /// `opensExternalLinksInAppEffective`.
    var openExternalLinksInApp: Bool?

    /// Report the page as focused even while Paguro is in the background, so a
    /// service that flips your status to "away" or "idle" on window blur
    /// (Microsoft Teams and the like) keeps showing you as active. Optional for
    /// SwiftData lightweight migration; nil is treated as off. Read via
    /// `staysActiveInBackgroundEffective`. Off by default because faking focus
    /// can make a service think you're already looking at it and hold back the
    /// desktop notifications Paguro forwards — an opt-in trade.
    var stayActiveInBackground: Bool?

    /// Whether the one-time "Passkeys aren't available for sign-in" notice has
    /// been shown for this service. Optional for SwiftData lightweight
    /// migration; nil is treated as "not yet seen" (see `needsPasskeyNotice`).
    /// A one-time launch backfill marks the services of a pre-existing install
    /// as seen, so the notice only appears for services added after this
    /// shipped — not retroactively for every service the user already had.
    var hasSeenPasskeyNotice: Bool?

    /// Per-service hibernation policy, stored raw for SwiftData lightweight
    /// migration. nil means "no per-service value set" — read via
    /// `hibernationPolicyEffective`, which migrates the legacy `neverHibernate`
    /// flag (true → `.never`) so existing "Keep Loaded" services are preserved.
    var hibernationPolicyRaw: String?

    /// Idle minutes before hibernation when the policy is `.after`. Optional for
    /// SwiftData lightweight migration; read via `hibernateAfterMinutesEffective`,
    /// which clamps to 1...120 (nil → 10). Ignored for the other policies.
    var hibernateAfterMinutes: Int?

    @Relationship(deleteRule: .cascade, inverse: \SpaceServiceLink.service)
    var spaceLinks: [SpaceServiceLink]

    var createdAt: Date
    var lastAccessedAt: Date

    /// Materialises the storage-optional zoom into a Double (nil → 1.0).
    var zoomLevelEffective: Double { pageZoom ?? 1.0 }

    /// Materialises the storage-optional force-dark flag (nil → false).
    var isForceDarkModeEnabled: Bool { forceDarkMode ?? false }

    /// The appearance signal for this service. Automatic is the default.
    var webAppearance: ServiceAppearanceMode {
        ServiceAppearanceMode.resolving(
            storedRaw: darkModeRaw,
            legacyForceDark: forceDarkMode
        )
    }

    /// Whether the passkey-limitation notice still needs to be shown for this
    /// service (nil or false → not yet seen).
    var needsPasskeyNotice: Bool { !(hasSeenPasskeyNotice ?? false) }

    /// Materialises the storage-optional OS-notification flag (nil → true), so
    /// services created before this flag existed keep forwarding notifications.
    var notifiesOSEffective: Bool { osNotificationsEnabled ?? true }

    /// The service's own camera policy (nil → `.ask`). For in-hand reads and the
    /// editor; runtime resolution uses `cameraPolicyRaw` + the global default.
    var cameraPolicy: MediaPermissionPolicy {
        get { cameraPolicyRaw.flatMap(MediaPermissionPolicy.init(rawValue:)) ?? .ask }
        set { cameraPolicyRaw = newValue.rawValue }
    }

    /// The service's own microphone policy (nil → `.ask`). See `cameraPolicy`.
    var microphonePolicy: MediaPermissionPolicy {
        get { microphonePolicyRaw.flatMap(MediaPermissionPolicy.init(rawValue:)) ?? .ask }
        set { microphonePolicyRaw = newValue.rawValue }
    }

    /// Materialises the storage-optional in-app-links flag (nil → false), so
    /// existing services keep opening external links in the system browser.
    var opensExternalLinksInAppEffective: Bool { openExternalLinksInApp ?? false }

    /// Materialises the storage-optional stay-active flag (nil → false), so a
    /// service only fakes focus when the user has explicitly opted in.
    var staysActiveInBackgroundEffective: Bool { stayActiveInBackground ?? false }

    /// Catalog categories whose services must never auto-hibernate (chat apps).
    /// A hibernated web app can only refresh its badge on the periodic sweep, not
    /// fire an instant alert, so chat apps stay live even when a per-service timer
    /// is set — you need to hear from them the moment a message lands.
    static let notificationCriticalCategories: Set<String> = ["Messaging"]

    /// True when this service must stay live for real-time notifications, decided
    /// by its catalog category. Custom (non-catalog) services aren't covered —
    /// use the `.never` hibernation policy for those.
    var isNotificationCritical: Bool {
        guard let catalogEntryID,
              let entry = ServiceCatalog.shared.entry(for: catalogEntryID)
        else { return false }
        return Self.notificationCriticalCategories.contains(entry.category)
    }

    /// The effective hibernation policy. An explicit `hibernationPolicyRaw` wins;
    /// otherwise a legacy `neverHibernate == true` service maps to `.never`
    /// (preserving "Keep Loaded"), and everything else — including an unknown
    /// stored value — defaults to `.followGlobal`.
    var hibernationPolicyEffective: HibernationPolicy {
        if let raw = hibernationPolicyRaw, let policy = HibernationPolicy(rawValue: raw) {
            return policy
        }
        return neverHibernate ? .never : .followGlobal
    }

    /// Idle minutes before hibernation for the `.after` policy, clamped to a sane
    /// 1...120 (nil → 10). Mirrors the global `autoHibernateIdleMinutesEffective`.
    var hibernateAfterMinutesEffective: Int {
        min(120, max(1, hibernateAfterMinutes ?? 10))
    }

    /// True if this service is muted directly, or via any space it belongs to
    /// (muting a space cascades to its members). Use this when the model object
    /// is already in hand — it avoids AppState's fetch-all-then-scan lookup.
    var isEffectivelyMuted: Bool {
        if isMuted { return true }
        // Skip links whose space is gone. `space` is nil once the space was
        // deleted and the cascade cleared this end; a link that survived an
        // older, unclean delete can still hold a freed model instead, and
        // reading it would fault, so keep the `modelContext` check too.
        return spaceLinks.contains { link in
            guard let space = link.space, space.modelContext != nil else { return false }
            return space.isMutedEffective
        }
    }

    init(
        id: UUID = UUID(),
        label: String,
        url: String,
        customIconData: Data? = nil,
        fetchedIconData: Data? = nil,
        faviconFetchedAt: Date? = nil,
        catalogEntryID: String? = nil,
        isMuted: Bool = false,
        showBadge: Bool = true,
        neverHibernate: Bool = false,
        userAgent: String? = nil,
        dataStoreIdentifier: UUID = UUID(),
        pageZoom: Double? = nil,
        osNotificationsEnabled: Bool? = nil,
        customCSS: String? = nil,
        forceDarkMode: Bool? = nil,
        darkModeRaw: String? = nil,
        hasSeenPasskeyNotice: Bool? = nil,
        cameraPolicyRaw: String? = nil,
        microphonePolicyRaw: String? = nil,
        openExternalLinksInApp: Bool? = nil,
        stayActiveInBackground: Bool? = nil,
        hibernationPolicyRaw: String? = nil,
        hibernateAfterMinutes: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.url = url
        self.customIconData = customIconData
        self.fetchedIconData = fetchedIconData
        self.faviconFetchedAt = faviconFetchedAt
        self.catalogEntryID = catalogEntryID
        self.isMuted = isMuted
        self.showBadge = showBadge
        self.neverHibernate = neverHibernate
        self.userAgent = userAgent
        self.dataStoreIdentifier = dataStoreIdentifier
        self.pageZoom = pageZoom
        self.osNotificationsEnabled = osNotificationsEnabled
        self.customCSS = customCSS
        self.forceDarkMode = forceDarkMode
        self.darkModeRaw = darkModeRaw
        self.hasSeenPasskeyNotice = hasSeenPasskeyNotice
        self.cameraPolicyRaw = cameraPolicyRaw
        self.microphonePolicyRaw = microphonePolicyRaw
        self.openExternalLinksInApp = openExternalLinksInApp
        self.stayActiveInBackground = stayActiveInBackground
        self.hibernationPolicyRaw = hibernationPolicyRaw
        self.hibernateAfterMinutes = hibernateAfterMinutes
        self.spaceLinks = []
        self.createdAt = Date()
        self.lastAccessedAt = Date()
    }
}
