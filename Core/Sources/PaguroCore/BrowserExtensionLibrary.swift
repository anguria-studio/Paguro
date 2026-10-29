import Foundation

/// Saved packages, compatibility profiles, and account-specific access choices.
public struct BrowserExtensionLibrary: Codable, Equatable, Sendable {
    public var records: [BrowserExtensionRecord]
    public var optionalAccess: [String: [String: ExtensionOptionalAccess]]
    public var profiles: [String: ExtensionRuntimeProfile]

    public init(records: [BrowserExtensionRecord], profiles: [String: ExtensionRuntimeProfile] = [:],
                optionalAccess: [String: [String: ExtensionOptionalAccess]] = [:]) {
        self.records = records
        self.profiles = profiles
        self.optionalAccess = optionalAccess
    }

    public var isValid: Bool {
        records.count <= 100 && records.allSatisfy(\.isValid)
            && Set(records.map(\.id)).count == records.count
            && Set(records.map(\.slug)).count == records.count
            && hasValidOptionalAccess && hasValidProfiles
    }

    /// Each choice belongs to an installed package and one of its assigned accounts.
    private var hasValidOptionalAccess: Bool {
        guard optionalAccess.count <= 100 else { return false }
        return optionalAccess.allSatisfy { extensionKey, accounts in
            guard let record = record(forKey: extensionKey), accounts.count <= 10_000 else { return false }
            return accounts.allSatisfy { serviceKey, access in
                guard let serviceID = Self.serviceID(forKey: serviceKey) else { return false }
                return record.serviceIDs.contains(serviceID) && access.packageSHA256 == record.sha256
                    && access.isValid && !access.isEmpty
            }
        }
    }

    /// Standard is the default, so only an assigned account's Firefox choice is saved.
    private var hasValidProfiles: Bool {
        let assigned = Set(records.flatMap(\.serviceIDs))
        return profiles.count <= 10_000 && profiles.allSatisfy { key, value in
            guard let serviceID = Self.serviceID(forKey: key) else { return false }
            return assigned.contains(serviceID) && value != .standard
        }
    }

    private func record(forKey key: String) -> BrowserExtensionRecord? {
        records.first { $0.id.uuidString == key }
    }

    /// Keys must be the canonical uppercase UUID text, so one account has one key.
    private static func serviceID(forKey key: String) -> UUID? {
        guard let id = UUID(uuidString: key), id.uuidString == key else { return nil }
        return id
    }

    public mutating func removeUnassignedProfiles() {
        let assigned = Set(records.flatMap(\.serviceIDs).map(\.uuidString))
        profiles = profiles.filter { assigned.contains($0.key) }
    }

    public mutating func removeUnassignedAccess() {
        for extensionKey in Array(optionalAccess.keys) {
            guard let record = record(forKey: extensionKey) else {
                optionalAccess[extensionKey] = nil
                continue
            }
            let accounts = optionalAccess[extensionKey, default: [:]].filter { key, access in
                guard let serviceID = Self.serviceID(forKey: key) else { return false }
                return record.serviceIDs.contains(serviceID) && access.packageSHA256 == record.sha256
                    && !access.isEmpty
            }
            optionalAccess[extensionKey] = accounts.isEmpty ? nil : accounts
        }
    }

    private enum CodingKeys: String, CodingKey { case version, records, profiles, optionalAccess }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        records = try values.decode([BrowserExtensionRecord].self, forKey: .records)
        profiles = try values.decodeIfPresent([String: ExtensionRuntimeProfile].self, forKey: .profiles) ?? [:]
        optionalAccess = try values.decodeIfPresent(
            [String: [String: ExtensionOptionalAccess]].self, forKey: .optionalAccess) ?? [:]
        guard (1...3).contains(version), (version != 1 || profiles.isEmpty),
              (version == 3 || optionalAccess.isEmpty), isValid else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Invalid extension library")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        guard isValid else {
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Invalid extension library")
            throw EncodingError.invalidValue(self, context)
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(3, forKey: .version)
        try values.encode(records, forKey: .records)
        try values.encode(profiles, forKey: .profiles)
        try values.encode(optionalAccess, forKey: .optionalAccess)
    }
}
