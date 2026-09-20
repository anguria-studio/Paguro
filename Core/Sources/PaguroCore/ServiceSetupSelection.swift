import Foundation

/// A service to create when the user finishes setup. No session exists yet.
public struct ServiceSetupDraft: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let url: String
    public let catalogEntryID: String?
    public let userAgent: String?
    public let customIconData: Data?
    public let fetchedIconData: Data?

    public init(
        id: String = UUID().uuidString,
        label: String,
        url: String,
        catalogEntryID: String? = nil,
        userAgent: String? = nil,
        customIconData: Data? = nil,
        fetchedIconData: Data? = nil
    ) {
        self.id = id
        self.label = label
        self.url = url
        self.catalogEntryID = catalogEntryID
        self.userAgent = userAgent
        self.customIconData = customIconData
        self.fetchedIconData = fetchedIconData
    }
}

/// Keeps the user's selection order independent of search and category filters.
public struct ServiceSetupSelection: Equatable, Sendable {
    public private(set) var services: [ServiceSetupDraft] = []

    public init() {}

    public func contains(_ id: String) -> Bool {
        services.contains { $0.id == id }
    }

    public mutating func toggle(_ draft: ServiceSetupDraft) {
        if contains(draft.id) {
            services.removeAll { $0.id == draft.id }
        } else {
            services.append(draft)
        }
    }
}
