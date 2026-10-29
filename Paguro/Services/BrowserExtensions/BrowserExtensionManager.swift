#if !APP_STORE
import AppKit
import Foundation
import Observation
import PaguroCore
import WebKit

@available(macOS 15.4, *)
@MainActor @Observable
final class BrowserExtensionManager: BrowserExtensionHosting {
    struct Preview {
        let id: UUID
        let package: FirefoxAddonPackage
        let webExtension: WKWebExtension
        let fileURL: URL
        let permissions: [String]
        /// Read on the main actor when the review starts, because WebKit isolates it there.
        let name: String
    }

    private(set) var records: [BrowserExtensionRecord] = []
    private(set) var optionalAccess: [String: [String: ExtensionOptionalAccess]] = [:]
    private(set) var profiles: [String: ExtensionRuntimeProfile] = [:]
    private(set) var preview: Preview?
    private(set) var isBusy = false
    var errorMessage: String?
    private(set) var failures: [UUID: String] = [:]
    private(set) var changeToken = 0
    private(set) var runtimeIssues: [UUID: [UUID: [String]]] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var extensions: [UUID: WKWebExtension] = [:]
    @ObservationIgnored private var sessions: [UUID: ServiceExtensionSession] = [:]
    @ObservationIgnored private var work: Task<Void, Never>?
    private(set) var isReviewing = false
    private var isStopped = false
    private var canWriteLibrary = false
    private var didLoadLibrary = false
    /// The saved library could not be read. Writing stays off so the file is
    /// not overwritten until the user chooses to reset it.
    private(set) var libraryIsUnreadable = false
    /// Saved packages that are still being verified after launch.
    @ObservationIgnored private var pendingIDs: Set<UUID> = []
    private var activeID: UUID?
    private var isLocked = false
    var updateChecks = ExtensionUpdateChecks()
    var updateCheckErrors: [UUID: String] = [:]
    var isCheckingUpdates = false
    @ObservationIgnored var updateMonitor: Task<Void, Never>?
    @ObservationIgnored var updateWork: Task<Void, Never>?
    var updateRun = UUID()
    var updatesStarted = false
    var now: () -> Date = Date.init
    var fetchRelease: @Sendable (FirefoxAddonSource) async throws -> FirefoxAddonRelease
    var fetchPackage: @Sendable (FirefoxAddonSource) async throws -> FirefoxAddonPackage


    var assignableServiceIDs: () -> Set<UUID> = { [] }
    var canRebuild: (Set<UUID>) -> Bool = { _ in true }
    var onAssignmentsChanged: (Set<UUID>) -> Void = { _ in }

    init(directory: URL,
         fetchRelease: @escaping @Sendable (FirefoxAddonSource) async throws -> FirefoxAddonRelease = { try await FirefoxAddonClient().latest($0) },
         fetchPackage: @escaping @Sendable (FirefoxAddonSource) async throws -> FirefoxAddonPackage = { try await FirefoxAddonClient().fetch($0) }) {
        self.directory = directory
        self.fetchRelease = fetchRelease
        self.fetchPackage = fetchPackage
    }

    var updateStateURL: URL { directory.appending(path: "update-checks.json") }
    private var libraryURL: URL { directory.appending(path: "library.json") }
    private static let maximumLibraryBytes = 2 * 1_024 * 1_024
    var permitsUpdateChecks: Bool { !isStopped && !isLocked && canWriteLibrary }


    func start() {
        guard work == nil, !isStopped else { return }
        isBusy = true
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.finishWork() }
            do { try await self.restore(); self.updatesStarted = true }
            catch { self.errorMessage = "Could not open the extension library. \(error.localizedDescription)" }
        }
    }

    func restore() async throws {
        try loadLibrary()
        try await loadPackages()
    }

    /// Reads assignments and profiles synchronously, so a service view created
    /// at launch gets its extension controller and browser identity at once.
    /// Packages load later and attach to that controller without a page rebuild.
    func loadLibrary() throws {
        guard !didLoadLibrary, !isStopped else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let library: BrowserExtensionLibrary
            do {
                let data = try boundedRead(libraryURL, limit: Self.maximumLibraryBytes)
                library = try JSONDecoder().decode(BrowserExtensionLibrary.self, from: data)
            } catch {
                libraryIsUnreadable = true
                throw error
            }
            records = library.records
            profiles = library.profiles
            optionalAccess = library.optionalAccess
        }
        didLoadLibrary = true
        canWriteLibrary = true
        pendingIDs = Set(records.map(\.id))
        restoreUpdateChecks()
    }

    private func loadPackages() async throws {
        for record in records where pendingIDs.contains(record.id) {
            try Task.checkCancellation()
            do {
                let url = directory.appending(path: record.packageName)
                let data = try boundedRead(url, limit: ExtensionArchivePolicy.maximumDownloadBytes)
                guard FirefoxAddonClient.digest(data) == record.sha256 else { throw FirefoxAddonClient.Failure.invalidHash }
                try ExtensionArchivePolicy.validate(data)
                let webExtension = try await WKWebExtension(resourceBaseURL: url)
                try validate(webExtension)
                try Task.checkCancellation()
                guard records.contains(where: { $0.id == record.id && $0.sha256 == record.sha256 }) else { continue }
                extensions[record.id] = webExtension
                pendingIDs.remove(record.id)
                attachToOpenSessions(record.id)
            } catch is CancellationError { throw CancellationError() }
            catch {
                pendingIDs.remove(record.id)
                failures[record.id] = error.localizedDescription
            }
        }
        pendingIDs.removeAll()
    }

    /// WebKit injects content scripts into pages that are already open when a
    /// context loads, so a late package does not need a service reload.
    private func attachToOpenSessions(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), let webExtension = extensions[id] else { return }
        for serviceID in record.serviceIDs {
            guard let session = sessions[serviceID], session.contexts[id] == nil else { continue }
            do {
                try session.load(webExtension, id: id, packageSHA256: record.sha256,
                                 optionalAccess: optionalAccess[id.uuidString]?[serviceID.uuidString])
            } catch { failures[id] = error.localizedDescription }
        }
        changeToken &+= 1
    }

    func review(link: String) {
        guard !isBusy, !isStopped, !isLocked, canWriteLibrary else { return }
        discardPreview()
        errorMessage = nil
        isBusy = true
        isReviewing = true
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.finishWork() }
            do {
                let source = try FirefoxAddonSource(link: link)
                let package = try await self.fetchPackage(source)
                try Task.checkCancellation()
                try await self.prepare(package)
            } catch is CancellationError { }
            catch { self.errorMessage = error.localizedDescription }
        }
    }

    func prepare(_ package: FirefoxAddonPackage) async throws {
        try ExtensionArchivePolicy.validate(package.data)
        guard FirefoxAddonClient.digest(package.data) == package.sha256 else {
            throw FirefoxAddonClient.Failure.invalidHash
        }
        let id = records.first { $0.slug == package.slug }?.id ?? UUID()
        let url = directory.appending(path: "\(id.uuidString)-\(package.sha256).zip")
        do {
            try package.data.write(to: url, options: .atomic)
            let webExtension = try await WKWebExtension(resourceBaseURL: url)
            try validate(webExtension)
            guard webExtension.version == package.version else { throw Failure.invalidLibrary }
            try Task.checkCancellation()
            guard !isStopped else { throw CancellationError() }
            preview = Preview(id: id, package: package, webExtension: webExtension, fileURL: url,
                              permissions: Self.permissionSummary(webExtension),
                              name: webExtension.displayName ?? package.slug)
        } catch {
            removeUncommittedPackage(url)
            throw error
        }
    }

    @discardableResult
    func installPreview(serviceIDs: Set<UUID>) -> Bool {
        guard let preview, !isBusy, !isStopped, canWriteLibrary else { return false }
        errorMessage = nil
        let existing = records.first { $0.slug == preview.package.slug }
        let assigned = serviceIDs.intersection(assignableServiceIDs())
        guard !assigned.isEmpty else { errorMessage = "Choose at least one service."; return false }
        let affected = assigned.union(existing?.serviceIDs ?? [])
        guard canRebuild(affected) else { errorMessage = Failure.activeMedia.localizedDescription; return false }
        let record = BrowserExtensionRecord(
            id: preview.id, slug: preview.package.slug, name: preview.name,
            version: preview.package.version, sha256: preview.package.sha256,
            permissions: preview.permissions, serviceIDs: assigned
        )
        guard record.isValid, existing != nil || records.count < 100 else {
            errorMessage = Failure.invalidLibrary.localizedDescription
            return false
        }
        let destination = directory.appending(path: record.packageName)
        let alreadyExists = FileManager.default.fileExists(atPath: destination.path)
        do {
            try save(records: records.filter { $0.id != record.id } + [record])
            extensions[record.id] = preview.webExtension
            failures.removeValue(forKey: record.id)
            refreshUpdateChecks()
            onAssignmentsChanged(affected)
            discardPreview()
            if let existing, existing.packageName != record.packageName {
                try? FileManager.default.removeItem(at: directory.appending(path: existing.packageName))
            }
            return true
        } catch {
            if !alreadyExists { try? FileManager.default.removeItem(at: destination) }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func assign(_ id: UUID, to serviceIDs: Set<UUID>) -> Bool {
        guard !isBusy, !isStopped, canWriteLibrary,
              let index = records.firstIndex(where: { $0.id == id }) else { return false }
        errorMessage = nil
        let assigned = serviceIDs.intersection(assignableServiceIDs())
        let affected = records[index].serviceIDs.symmetricDifference(assigned)
        guard canRebuild(affected) else { errorMessage = Failure.activeMedia.localizedDescription; return false }
        var next = records
        next[index].serviceIDs = assigned
        do {
            try save(records: next)
            onAssignmentsChanged(affected)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func remove(_ id: UUID) {
        guard !isBusy, !isStopped, canWriteLibrary, let record = records.first(where: { $0.id == id }) else { return }
        errorMessage = nil
        guard canRebuild(record.serviceIDs) else { errorMessage = Failure.activeMedia.localizedDescription; return }
        do {
            try save(records: records.filter { $0.id != id })
            extensions.removeValue(forKey: id)
            failures.removeValue(forKey: id)
            refreshUpdateChecks()
            onAssignmentsChanged(record.serviceIDs)
            try? FileManager.default.removeItem(at: directory.appending(path: record.packageName))
        } catch { errorMessage = error.localizedDescription }
    }

    /// Keeps the unreadable file next to the library for inspection, removes
    /// the packages it referenced, and starts again with an empty library.
    func resetUnreadableLibrary() {
        guard libraryIsUnreadable, !isStopped, !isBusy else { return }
        let fileManager = FileManager.default
        let kept = directory.appending(path: "library-unreadable-\(UUID().uuidString).json")
        do {
            try fileManager.moveItem(at: libraryURL, to: kept)
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for package in files where package.pathExtension == "zip" { try? fileManager.removeItem(at: package) }
        } catch {
            errorMessage = "Could not reset the extension library. \(error.localizedDescription)"
            return
        }
        libraryIsUnreadable = false
        errorMessage = nil
        start()
    }

    func cancelReview() {
        if isReviewing { work?.cancel() }
        discardPreview()
    }

    func discardPreview() {
        if let preview { removeUncommittedPackage(preview.fileURL) }
        preview = nil
    }

    private func removeUncommittedPackage(_ url: URL) {
        guard !records.contains(where: { $0.packageName == url.lastPathComponent }) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func finishWork() {
        isBusy = false
        isReviewing = false
        work = nil
        resumeUpdateChecks()
    }

    /// Writes the library atomically, then applies it. A failed write changes nothing.
    /// Choices for accounts that lost their assignment are dropped on the way.
    private func save(records: [BrowserExtensionRecord]? = nil,
                      profiles: [String: ExtensionRuntimeProfile]? = nil,
                      optionalAccess: [String: [String: ExtensionOptionalAccess]]? = nil) throws {
        var library = BrowserExtensionLibrary(records: records ?? self.records,
                                              profiles: profiles ?? self.profiles,
                                              optionalAccess: optionalAccess ?? self.optionalAccess)
        library.removeUnassignedProfiles()
        library.removeUnassignedAccess()
        let data = try JSONEncoder().encode(library)
        guard data.count <= Self.maximumLibraryBytes else { throw Failure.invalidLibrary }
        try data.write(to: libraryURL, options: .atomic)
        self.records = library.records
        self.profiles = library.profiles
        self.optionalAccess = library.optionalAccess
    }

    func profile(for serviceID: UUID) -> ExtensionRuntimeProfile { profiles[serviceID.uuidString] ?? .standard }

    @discardableResult
    func setProfile(_ profile: ExtensionRuntimeProfile, for serviceID: UUID) -> Bool {
        guard !isBusy, !isStopped, !isLocked, canWriteLibrary, assignableServiceIDs().contains(serviceID),
              records.contains(where: { $0.serviceIDs.contains(serviceID) }) else { return false }
        errorMessage = nil
        guard profile != self.profile(for: serviceID) else { return true }
        guard canRebuild([serviceID]) else { errorMessage = Failure.activeMedia.localizedDescription; return false }
        var next = profiles
        next[serviceID.uuidString] = profile == .standard ? nil : profile
        do {
            try save(profiles: next)
            onAssignmentsChanged([serviceID])
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @discardableResult
    func saveOptionalAccess(_ access: ExtensionOptionalAccess, extensionID: UUID, serviceID: UUID) -> Bool {
        guard !isStopped, canWriteLibrary, assignableServiceIDs().contains(serviceID),
              let record = records.first(where: { $0.id == extensionID && $0.serviceIDs.contains(serviceID) }),
              access.packageSHA256 == record.sha256, access.isValid else { return false }
        let old = optionalAccess[extensionID.uuidString]?[serviceID.uuidString]
        let onlyRemovesAccess = access.permissions.isSubset(of: old?.permissions ?? [])
            && access.origins.isSubset(of: old?.origins ?? [])
        guard onlyRemovesAccess || (!isLocked && !isBusy) else { return false }
        var next = optionalAccess
        var accounts = next[extensionID.uuidString, default: [:]]
        accounts[serviceID.uuidString] = access.isEmpty ? nil : access
        next[extensionID.uuidString] = accounts.isEmpty ? nil : accounts
        do {
            try save(optionalAccess: next)
            return true
        } catch {
            errorMessage = "Could not save extension access. Retry before restarting Paguro."
            return false
        }
    }

    func resetOptionalAccess(_ extensionID: UUID) {
        guard !isStopped, !isLocked, !isBusy, canWriteLibrary else { return }
        var next = optionalAccess
        next[extensionID.uuidString] = nil
        do {
            try save(optionalAccess: next)
            for session in sessions.values { session.resetOptionalAccess(extensionID) }
        } catch { errorMessage = error.localizedDescription }
    }

    func customUserAgent(defaultValue: String, for serviceID: UUID) -> String? {
        (sessions[serviceID]?.profile ?? .standard).customUserAgent(defaultValue: defaultValue)
    }

    private func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw Failure.invalidLibrary }
        return data
    }

    private func validate(_ webExtension: WKWebExtension) throws {
        guard webExtension.errors.isEmpty else {
            throw Failure.unsupported(webExtension.errors.map(\.localizedDescription).joined(separator: "\n"))
        }
    }

    static func permissionSummary(_ webExtension: WKWebExtension) -> [String] {
        let required = webExtension.requestedPermissions.map(\.rawValue)
            + webExtension.allRequestedMatchPatterns.map(\.string)
        let optional = webExtension.optionalPermissions.map { "Optional: \($0.rawValue)" }
            + webExtension.optionalPermissionMatchPatterns.map { "Optional: \($0.string)" }
        return Set(required + optional).sorted()
    }

    func configure(_ configuration: WKWebViewConfiguration, for service: ServiceInstance) {
        guard !isStopped else { return }
        let selected = records.filter {
            $0.serviceIDs.contains(service.id) && (extensions[$0.id] != nil || pendingIDs.contains($0.id))
        }
        guard !selected.isEmpty else { return }
        // A replaced session would keep its background pages running.
        sessions.removeValue(forKey: service.id)?.close()
        let session = ServiceExtensionSession(serviceID: service.id,
            storeID: service.dataStoreIdentifier, dataStore: configuration.websiteDataStore, serviceName: service.label,
            profile: profile(for: service.id))
        if let name = session.profile.applicationNameForUserAgent { configuration.applicationNameForUserAgent = name }
        session.saveOptionalAccess = { [weak self] id, access in
            self?.saveOptionalAccess(access, extensionID: id, serviceID: service.id) == true
        }
        for record in selected {
            guard let webExtension = extensions[record.id] else { continue }
            do { try session.load(webExtension, id: record.id, packageSHA256: record.sha256, optionalAccess: optionalAccess[record.id.uuidString]?[service.id.uuidString]) }
            catch { failures[record.id] = error.localizedDescription }
        }
        session.onIssuesChanged = { [weak self, weak session] in
            guard let self, let session else { return }
            self.runtimeIssues[service.id] = session.runtimeIssues
            self.changeToken &+= 1
        }
        runtimeIssues[service.id] = session.runtimeIssues
        session.onActionChanged = { [weak self] in self?.changeToken &+= 1 }
        sessions[service.id] = session
        configuration.webExtensionController = session.controller
    }

    func didCreate(_ webView: WKWebView, for serviceID: UUID) {
        sessions[serviceID]?.open(webView)
    }

    func didActivate(_ serviceID: UUID?) {
        activeID = serviceID
        for (id, session) in sessions { session.setActive(!isLocked && id == serviceID) }
        changeToken &+= 1
    }

    func didNavigate(_ serviceID: UUID) { sessions[serviceID]?.didNavigate() }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        if locked { cancelReview(); suspendUpdateChecks() }
        else { resumeUpdateChecks() }
        didActivate(activeID)
    }

    func release(_ serviceID: UUID) {
        sessions.removeValue(forKey: serviceID)?.close()
        runtimeIssues.removeValue(forKey: serviceID)
        changeToken &+= 1
    }

    func actions(for serviceID: UUID) -> [(id: UUID, action: WKWebExtension.Action)] {
        _ = changeToken
        return sessions[serviceID]?.actions ?? []
    }

    func hasOptions(_ id: UUID, for serviceID: UUID) -> Bool {
        _ = changeToken
        return sessions[serviceID]?.contexts[id]?.optionsPageURL != nil
    }

    func showDiagnostics(_ id: UUID, for serviceID: UUID, from anchor: NSView) {
        guard !isStopped, !isLocked else { return }
        sessions[serviceID]?.showDiagnostics(id, from: anchor)
    }

    func openOptions(_ id: UUID, for serviceID: UUID, from anchor: NSView) {
        guard !isStopped, !isLocked else { return }
        sessions[serviceID]?.openOptions(id, from: anchor)
    }

    func extensionMenuItems(_ id: UUID, for serviceID: UUID) -> [NSMenuItem] {
        guard !isStopped, !isLocked else { return [] }
        return sessions[serviceID]?.menuItems(id) ?? []
    }

    func performAction(_ id: UUID, for serviceID: UUID, from anchor: NSView) {
        guard !isStopped, !isLocked else { return }
        sessions[serviceID]?.perform(id, from: anchor)
    }

    func shutdown() {
        guard !isStopped else { return }
        isStopped = true
        suspendUpdateChecks()
        work?.cancel()
        discardPreview()
        for session in sessions.values { session.close() }
        sessions.removeAll()
        runtimeIssues.removeAll()
        extensions.removeAll()
        pendingIDs.removeAll()
    }

    enum Failure: Error, LocalizedError {
        case invalidLibrary, activeMedia, unsupported(String)
        var errorDescription: String? {
            switch self {
            case .invalidLibrary: "The extension library is invalid or exceeds the prototype's limits."
            case .activeMedia: "Stop calls and media in the affected services before changing extensions."
            case .unsupported(let details): "WebKit cannot load this extension. \(details)"
            }
        }
    }
}
#endif
