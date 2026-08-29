import WebKit

/// Provides one persistent WebKit data store for each service account.
///
/// WebKit uses the identifier to keep the session data on disk. The cache also
/// prevents Blatta from making more store objects than it needs.
@MainActor
final class DataStoreManager {
    private var cache: [UUID: WKWebsiteDataStore] = [:]

    func dataStore(for instance: ServiceInstance) -> WKWebsiteDataStore {
        dataStore(forIdentifier: instance.dataStoreIdentifier)
    }

    func dataStore(forIdentifier identifier: UUID) -> WKWebsiteDataStore {
        if let cached = cache[identifier] {
            return cached
        }

        let store = WKWebsiteDataStore(forIdentifier: identifier)
        cache[identifier] = store
        return store
    }

    /// Removes a store object from the cache.
    ///
    /// Call this method before you remove the data store from disk.
    func evict(identifier: UUID) {
        cache.removeValue(forKey: identifier)
    }

    // Do not remove a data store while a web view uses it. WebKit can crash.
    // WebsiteDataReclaimer first marks the store as unused. It removes the
    // store later, after the related web view has been released.
}
