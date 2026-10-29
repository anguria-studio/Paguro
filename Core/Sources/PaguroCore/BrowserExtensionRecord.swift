import Foundation

public struct BrowserExtensionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let slug: String
    public let name: String
    public let version: String
    public let sha256: String
    public let permissions: [String]
    public var serviceIDs: Set<UUID>

    public init(id: UUID = UUID(), slug: String, name: String, version: String,
                sha256: String, permissions: [String], serviceIDs: Set<UUID>) {
        self.id = id
        self.slug = slug
        self.name = name
        self.version = version
        self.sha256 = sha256
        self.permissions = permissions
        self.serviceIDs = serviceIDs
    }

    public var packageName: String { "\(id.uuidString)-\(sha256).zip" }

    public var isValid: Bool {
        FirefoxAddonSource.isValidSlug(slug)
            && (1...256).contains(name.utf8.count) && (1...128).contains(version.utf8.count)
            && PackageDigest.isValidSHA256(sha256)
            && permissions.count <= 1_024 && permissions.allSatisfy { $0.utf8.count <= 2_048 }
            && serviceIDs.count <= 10_000
    }
}
