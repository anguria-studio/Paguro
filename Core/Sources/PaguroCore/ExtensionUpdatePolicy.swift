import Foundation

/// Metadata is an update hint. Installation must fetch and review the package again.
public struct FirefoxAddonRelease: Codable, Equatable, Sendable {
    public let slug: String
    public let version: String
    public let sha256: String
    public let downloadURL: URL
    public let size: Int

    public init(slug: String, version: String, sha256: String, downloadURL: URL, size: Int) {
        self.slug = slug
        self.version = version
        self.sha256 = sha256
        self.downloadURL = downloadURL
        self.size = size
    }

    public var isValid: Bool {
        FirefoxAddonSource.isValidSlug(slug) && (1...128).contains(version.utf8.count)
            && version.utf8.allSatisfy { (33...126).contains($0) }
            && PackageDigest.isValidSHA256(sha256)
            && downloadURL.absoluteString.utf8.count <= 8_192
            && FirefoxAddonSource.isTrustedDownloadURL(downloadURL)
            && (1...ExtensionArchivePolicy.maximumDownloadBytes).contains(size)
    }
}

public enum ExtensionUpdatePolicy {
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let pollInterval: TimeInterval = 60 * 60

    public static func shouldCheck(_ record: BrowserExtensionRecord, entry: ExtensionUpdateCheck?, now: Date) -> Bool {
        guard let entry, entry.installedSHA256 == record.sha256 else { return true }
        let elapsed = now.timeIntervalSince(entry.checkedAt)
        return elapsed < 0 || elapsed >= checkInterval
    }

    public static func isUpdate(_ release: FirefoxAddonRelease, for record: BrowserExtensionRecord) -> Bool {
        release.isValid && release.slug == record.slug && release.sha256 != record.sha256
            && FirefoxExtensionVersion.compare(release.version, record.version) == .orderedDescending
    }
}

public struct ExtensionUpdateCheck: Codable, Equatable, Sendable {
    public let installedSHA256: String
    public let checkedAt: Date
    public let available: FirefoxAddonRelease?

    public init(installedSHA256: String, checkedAt: Date, available: FirefoxAddonRelease?) {
        self.installedSHA256 = installedSHA256
        self.checkedAt = checkedAt
        self.available = available
    }

    public var isValid: Bool {
        PackageDigest.isValidSHA256(installedSHA256)
            && checkedAt.timeIntervalSince1970.isFinite && (available?.isValid ?? true)
    }
}

public struct ExtensionUpdateChecks: Codable, Equatable, Sendable {
    public var version = 1
    public var isEnabled = true
    public var entries: [String: ExtensionUpdateCheck] = [:]

    public init() {}

    public var isValid: Bool {
        version == 1 && entries.count <= 100 && entries.allSatisfy { key, entry in
            UUID(uuidString: key)?.uuidString == key && entry.isValid
        }
    }

    public mutating func prune(for records: [BrowserExtensionRecord]) {
        entries = entries.filter { key, entry in
            records.contains { $0.id.uuidString == key && $0.sha256 == entry.installedSHA256 }
        }
    }
}
