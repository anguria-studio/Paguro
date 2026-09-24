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
    /// True when the user marked a custom website as a chat app. False
    /// leaves the catalog category in charge (see `ChatAppRule`).
    public let isChatApp: Bool

    public init(
        id: String = UUID().uuidString,
        label: String,
        url: String,
        catalogEntryID: String? = nil,
        userAgent: String? = nil,
        customIconData: Data? = nil,
        fetchedIconData: Data? = nil,
        isChatApp: Bool = false
    ) {
        self.id = id
        self.label = label
        self.url = url
        self.catalogEntryID = catalogEntryID
        self.userAgent = userAgent
        self.customIconData = customIconData
        self.fetchedIconData = fetchedIconData
        self.isChatApp = isChatApp
    }
}

/// Keeps the user's selection order independent of search and category filters.
public struct ServiceSetupSelection: Equatable, Sendable {
    public var workspaceName = WorkspaceName.defaultValue
    public private(set) var services: [ServiceSetupDraft] = []
    /// Custom cards remain available after they are unchecked.
    public private(set) var customWebsites: [ServiceSetupDraft] = []

    public init() {}

    /// Continue and final save share the same draft requirements.
    public var canCreateWorkspace: Bool {
        !services.isEmpty && WorkspaceName.normalized(workspaceName) != nil
    }

    public func contains(_ id: String) -> Bool {
        services.contains { $0.id == id }
    }

    public func matchingCustomWebsites(search: String) -> [ServiceSetupDraft] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return customWebsites.filter {
            query.isEmpty || "\($0.label) \($0.url) Custom websites".localizedStandardContains(query)
        }
    }

    public mutating func toggle(_ draft: ServiceSetupDraft) {
        if draft.catalogEntryID == nil && !customWebsites.contains(where: { $0.id == draft.id }) {
            customWebsites.append(draft)
        }
        if contains(draft.id) {
            services.removeAll { $0.id == draft.id }
        } else {
            services.append(draft)
        }
    }
}
