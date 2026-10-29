import Foundation

/// Explicit optional access choices for one package and service account.
public struct ExtensionOptionalAccess: Codable, Equatable, Sendable {
    public let packageSHA256: String
    public var permissions: Set<String> = []
    public var origins: Set<String> = []
    public var deniedPermissions: Set<String> = []
    public var deniedOrigins: Set<String> = []

    public init(packageSHA256: String) { self.packageSHA256 = packageSHA256 }

    public var isEmpty: Bool {
        permissions.isEmpty && origins.isEmpty && deniedPermissions.isEmpty && deniedOrigins.isEmpty
    }

    public var isValid: Bool {
        let entries = permissions.union(origins).union(deniedPermissions).union(deniedOrigins)
        return PackageDigest.isValidSHA256(packageSHA256)
            && entries.count <= 1_024
            && entries.allSatisfy(Self.isValidEntry)
            && permissions.isDisjoint(with: deniedPermissions)
            && origins.isDisjoint(with: deniedOrigins)
    }

    private static func isValidEntry(_ entry: String) -> Bool {
        !entry.isEmpty && entry.utf8.count <= 2_048
            && !entry.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    public mutating func record(permissions requestedPermissions: Set<String>, origins requestedOrigins: Set<String>, allowed: Bool) {
        permissions.subtract(requestedPermissions)
        deniedPermissions.subtract(requestedPermissions)
        origins.subtract(requestedOrigins)
        deniedOrigins.subtract(requestedOrigins)
        if allowed {
            permissions.formUnion(requestedPermissions)
            origins.formUnion(requestedOrigins)
        } else {
            deniedPermissions.formUnion(requestedPermissions)
            deniedOrigins.formUnion(requestedOrigins)
        }
    }
}
