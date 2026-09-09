import Foundation

public enum ConfigurationImportMode: String, CaseIterable, Sendable {
    case add
    case replace
}

/// Portable settings only. Browser storage identifiers and session data have no fields here.
public struct ConfigurationArchive: Codable, Equatable, Sendable {
    public var format = "blatta-configuration"
    public var version = 1
    public var workspaces: [ConfigurationWorkspace] = []
    public var services: [ConfigurationService] = []
    public var preferences = ConfigurationPreferences()
    public init() {}
}

public struct ConfigurationWorkspace: Codable, Equatable, Sendable {
    public var id = UUID()
    public var name = ""
    public var emoji = ""
    public var isMuted = false
    /// Array order defines service order. Shared IDs keep shared accounts intact.
    public var serviceIDs: [UUID] = []
    public init() {}
}

public struct ConfigurationService: Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var label: String = ""
    public var url: String = ""
    public var customIconData: Data? = nil
    public var catalogEntryID: String? = nil
    public var isMuted: Bool = false
    public var showBadge: Bool = true
    public var userAgent: String? = nil
    public var pageZoom: Double? = nil
    public var osNotificationsEnabled: Bool = true
    public var customCSS: String? = nil
    public var appearance: String = "automatic"
    public var cameraPolicy: String? = nil
    public var microphonePolicy: String? = nil
    public var openExternalLinksInApp: Bool = false
    public var stayActiveInBackground: Bool = false
    public var hibernationPolicy: String = "followGlobal"
    public var hibernateAfterMinutes: Int = 10
    public init() {}
}

public struct ConfigurationPreferences: Codable, Equatable, Sendable {
    public var appPresenceMode: String = "both"
    public var showBadgeCountInDock: Bool = true
    public var autoDismissCookieBanners: Bool = false
    public var defaultZoom: Double = 1
    public var scheduledDNDEnabled: Bool = false
    public var dndStartMinutes: Int = 1320
    public var dndEndMinutes: Int = 420
    public var appLockEnabled: Bool = false
    public var lockOnLaunch: Bool = true
    public var lockOnSleep: Bool = true
    public var railLayout: String = "sidebar"
    public var appearanceMode: String = "system"
    public var contentBlockingEnabled: Bool = true
    public var annoyanceBlockingEnabled: Bool = false
    public var defaultCameraPolicy: String = "ask"
    public var defaultMicrophonePolicy: String = "ask"
    public var googleFaviconFallbackEnabled: Bool = false
    public var autoHibernateIdleEnabled: Bool = false
    public var autoHibernateIdleMinutes: Int = 10
    public var liquidGlassStyle: String = "regular"
    public var liquidGlassIntensity: Double = 1
    public var iconRailBaseSize: Double = 22
    public var iconRailMagnification: Double = 0.26
    public var iconRailPosition: String = "top"
    public var workspaceViewMode: String = "current"
    public var railBarIconsOnly: Bool = false
    public var sidebarCollapsed: Bool = false
    public var systemNotifications: Bool = true
    public var islandNotifications: Bool = false
    public init() {}
}

public enum ConfigurationArchiveError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        if case let .invalid(message) = self { return message }
        return nil
    }
}

/// Validates the complete file before the application changes any records.
public enum ConfigurationArchiveCodec {
    public static let maximumBytes = 20 * 1024 * 1024

    public static func decode(_ data: Data) throws -> ConfigurationArchive {
        guard data.count <= maximumBytes else { throw invalid("The configuration file exceeds 20 MB.") }
        let archive: ConfigurationArchive
        do { archive = try JSONDecoder().decode(ConfigurationArchive.self, from: data) }
        catch { throw invalid("This is not a complete Blatta configuration file.") }
        try validate(archive)
        return archive
    }

    public static func encode(_ archive: ConfigurationArchive) throws -> Data {
        try validate(archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw invalid("The configuration file exceeds 20 MB.") }
        return data
    }

    public static func validate(_ archive: ConfigurationArchive) throws {
        guard archive.format == "blatta-configuration", archive.version == 1 else {
            throw invalid("This configuration format is not supported. Update Blatta and try again.")
        }
        guard archive.workspaces.count <= 100, archive.services.count <= 500 else {
            throw invalid("A configuration can contain up to 100 workspaces and 500 services.")
        }
        let serviceIDs = Set(archive.services.map(\.id))
        guard serviceIDs.count == archive.services.count,
              Set(archive.workspaces.map(\.id)).count == archive.workspaces.count else {
            throw invalid("The configuration contains duplicate identifiers.")
        }
        for workspace in archive.workspaces {
            try text(workspace.name, maximum: 256, required: true)
            try text(workspace.emoji, maximum: 64)
            guard workspace.serviceIDs.count <= 500,
                  Set(workspace.serviceIDs).count == workspace.serviceIDs.count,
                  Set(workspace.serviceIDs).isSubset(of: serviceIDs) else {
                throw invalid("A workspace contains duplicate or missing service references.")
            }
        }
        for service in archive.services {
            try text(service.label, maximum: 256, required: true)
            try text(service.url, maximum: 8192, required: true)
            guard case .valid = CustomServiceInputValidator.validate(label: service.label, url: service.url),
                  let url = URLComponents(string: service.url), url.user == nil, url.password == nil else {
                throw invalid("Each service needs an HTTP or HTTPS URL without embedded credentials.")
            }
            try text(service.userAgent ?? "", maximum: 2048)
            try text(service.catalogEntryID ?? "", maximum: 256)
            guard (service.customCSS?.utf8.count ?? 0) <= 65_536,
                  (service.customIconData?.count ?? 0) <= 1_048_576 else {
                throw invalid("A service icon or custom stylesheet is too large.")
            }
            if let zoom = service.pageZoom { try number(zoom, in: 0.5...3) }
            try choice(service.appearance, in: ["automatic", "light", "dark"])
            try choice(service.cameraPolicy ?? "ask", in: ["ask", "allow", "deny"])
            try choice(service.microphonePolicy ?? "ask", in: ["ask", "allow", "deny"])
            try choice(service.hibernationPolicy, in: ["followGlobal", "never", "immediate", "after"])
            try number(Double(service.hibernateAfterMinutes), in: 1...120)
        }
        let p = archive.preferences
        try choice(p.appPresenceMode, in: ["dock", "menuBar", "both"])
        try choice(p.railLayout, in: ["sidebar", "topBars", "workspacesLeft", "servicesLeft"])
        try choice(p.appearanceMode, in: ["system", "light", "dark"])
        try choice(p.defaultCameraPolicy, in: ["ask", "allow", "deny"])
        try choice(p.defaultMicrophonePolicy, in: ["ask", "allow", "deny"])
        try choice(p.liquidGlassStyle, in: ["off", "clear", "regular"])
        try choice(p.iconRailPosition, in: ["top", "center"])
        try choice(p.workspaceViewMode, in: ["current", "all"])
        try number(p.defaultZoom, in: 0.5...3)
        try number(Double(p.dndStartMinutes), in: 0...1439)
        try number(Double(p.dndEndMinutes), in: 0...1439)
        try number(Double(p.autoHibernateIdleMinutes), in: 1...120)
        try number(p.liquidGlassIntensity, in: 0...1)
        try number(p.iconRailBaseSize, in: 14...44)
        try number(p.iconRailMagnification, in: 0...1)
    }

    private static func invalid(_ message: String) -> ConfigurationArchiveError { .invalid(message) }
    private static func text(_ value: String, maximum: Int, required: Bool = false) throws {
        guard value.utf8.count <= maximum,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("The configuration contains an empty, oversized, or invalid text field.")
        }
    }
    private static func choice(_ value: String, in choices: [String]) throws {
        guard choices.contains(value) else { throw invalid("The configuration contains an unknown setting value.") }
    }
    private static func number(_ value: Double, in range: ClosedRange<Double>) throws {
        guard value.isFinite, range.contains(value) else { throw invalid("A configuration setting is outside its allowed range.") }
    }
}
