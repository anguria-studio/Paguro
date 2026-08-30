import Foundation
import SwiftData
import BlattaCore

/// Owns SwiftData queries and mutations for workspaces and services.
///
/// Runtime controllers consume the plain outcomes returned here. They do not
/// start irreversible WebKit work until the related model save succeeds.
@MainActor
final class WorkspaceStore {
    struct ServiceMoveOutcome: Equatable {
        let serviceID: UUID
        let sourceSpaceID: UUID
        let targetSpaceID: UUID
    }

    struct ServiceDeletionOutcome: Equatable {
        let serviceID: UUID
        let dataStoreIdentifier: UUID
    }

    struct LinkRemovalOutcome: Equatable {
        let serviceID: UUID
        let orphanedDataStoreIdentifier: UUID?

        var deletedService: Bool { orphanedDataStoreIdentifier != nil }
    }

    struct SpaceDeletionOutcome: Equatable {
        let reclaimedServiceIDs: [UUID]
        let orphanedDataStoreIdentifiers: [UUID]
        let remainingSpaceID: UUID?
    }

    struct WindowSelection: Equatable {
        let spaceID: UUID?
        let serviceID: UUID?
    }

    struct SeedOutcome: Equatable {
        let didSeed: Bool
        let selectedSpaceID: UUID?
    }

    struct DefaultZoomOutcome: Equatable {
        let zoom: Double
        let affectedServiceIDs: [UUID]
    }

    struct SessionTarget: Equatable {
        let dataStoreIdentifier: UUID
        let homeURL: URL?
    }

    private let context: ModelContext
    private let preferencesStore: PreferencesStore

    init(context: ModelContext, preferencesStore: PreferencesStore) {
        self.context = context
        self.preferencesStore = preferencesStore
    }

    func service(id: UUID) -> ServiceInstance? {
        var descriptor = FetchDescriptor<ServiceInstance>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allServices() -> [ServiceInstance] {
        do {
            return try context.fetch(FetchDescriptor<ServiceInstance>())
        } catch {
            AppLogger.dataStore.error("Failed to fetch services: \(error.localizedDescription)")
            return []
        }
    }

    func findServiceMatching(host: String, preferringSpace spaceID: UUID?) -> ServiceInstance? {
        let matches = allServices().filter { service in
            guard let serviceHost = URL(string: service.url)?.host else { return false }
            return WebRoutingPolicy.belongsToService(host, serviceHost: serviceHost)
        }
        guard matches.count > 1, let spaceID else { return matches.first }

        let matchingIDs = Set(matches.map(\.id))
        let serviceIDInPreferredSpace = (try? liveLinks())?.first {
            $0.space.id == spaceID && matchingIDs.contains($0.service.id)
        }?.service.id
        return serviceIDInPreferredSpace.flatMap { id in matches.first { $0.id == id } }
            ?? matches.first
    }

    func servicesForSpace(_ spaceID: UUID) -> [ServiceInstance] {
        do {
            return try liveLinks()
                .filter { $0.space.id == spaceID }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.service)
        } catch {
            AppLogger.dataStore.error(
                "Failed to fetch links for space \(spaceID): \(error.localizedDescription)"
            )
            return []
        }
    }

    func liveLinks() throws -> [SpaceServiceLink] {
        try context.fetch(FetchDescriptor<SpaceServiceLink>()).filter {
            $0.modelContext != nil
                && $0.space.modelContext != nil
                && $0.service.modelContext != nil
        }
    }

    static func memberships(from links: [SpaceServiceLink]) -> [UUID: Set<UUID>] {
        var memberships: [UUID: Set<UUID>] = [:]
        for link in links {
            memberships[link.service.id, default: []].insert(link.space.id)
        }
        return memberships
    }

    func orphanedServiceCount(byDeletingSpace spaceID: UUID) -> Int {
        let links = (try? liveLinks()) ?? []
        return WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: spaceID,
            memberships: Self.memberships(from: links)
        ).count
    }

    func commitServiceEdits(serviceID: UUID) -> ServiceInstance? {
        guard let service = service(id: serviceID),
              context.saveOrRollback(reason: "save service edits")
        else { return nil }
        return service
    }

    func sessionTarget(for serviceID: UUID) -> SessionTarget? {
        guard let service = service(id: serviceID) else { return nil }
        return SessionTarget(
            dataStoreIdentifier: service.dataStoreIdentifier,
            homeURL: URL(string: service.url)
        )
    }

    static func effectiveZoom(pageZoom: Double?, defaultZoom: Double) -> Double {
        pageZoom ?? defaultZoom
    }

    func setDefaultZoom(_ zoom: Double) -> DefaultZoomOutcome? {
        let clamped = max(0.5, min(3.0, zoom))
        guard preferencesStore.setDefaultZoom(clamped) else { return nil }
        return DefaultZoomOutcome(
            zoom: clamped,
            affectedServiceIDs: allServices().filter { $0.pageZoom == nil }.map(\.id)
        )
    }

    func setPageZoom(_ zoom: Double, for serviceID: UUID) -> Bool {
        guard let service = service(id: serviceID) else { return false }
        service.pageZoom = zoom
        return context.saveOrRollback(reason: "persist zoom")
    }

    func addService(
        label: String,
        url: String,
        catalogEntryID: String? = nil,
        userAgent: String? = nil,
        customIconData: Data? = nil,
        to spaceID: UUID
    ) throws -> UUID? {
        var descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceID })
        descriptor.fetchLimit = 1
        guard let space = try context.fetch(descriptor).first else { return nil }
        let nextOrder = ((try liveLinks())
            .filter { $0.space.id == spaceID }
            .map(\.sortOrder)
            .max() ?? -1) + 1

        let service = ServiceInstance(
            label: label,
            url: url,
            customIconData: customIconData,
            catalogEntryID: catalogEntryID,
            userAgent: userAgent
        )
        context.insert(service)
        context.insert(SpaceServiceLink(sortOrder: nextOrder, space: space, service: service))
        guard context.saveOrRollback(reason: "add service") else { return nil }
        return service.id
    }

    func moveService(linkID: UUID, to targetSpaceID: UUID) throws -> ServiceMoveOutcome? {
        let links = try liveLinks()
        guard let link = links.first(where: { $0.id == linkID }) else { return nil }
        let sourceSpaceID = link.space.id
        let serviceID = link.service.id
        guard sourceSpaceID != targetSpaceID else { return nil }

        var targetDescriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == targetSpaceID }
        )
        targetDescriptor.fetchLimit = 1
        guard let targetSpace = try context.fetch(targetDescriptor).first else { return nil }
        guard !links.contains(where: {
            $0.id != linkID
                && $0.service.id == serviceID
                && $0.space.id == targetSpaceID
        }) else { return nil }

        let targetOrders = links
            .filter { $0.space.id == targetSpaceID }
            .map(\.sortOrder)
        link.sortOrder = (targetOrders.max() ?? -1) + 1
        link.space = targetSpace
        guard context.saveOrRollback(reason: "move service") else { return nil }
        return ServiceMoveOutcome(
            serviceID: serviceID,
            sourceSpaceID: sourceSpaceID,
            targetSpaceID: targetSpaceID
        )
    }

    /// Moves a workspace among the others and saves the new order.
    ///
    /// The same rule as the services, on the workspaces themselves:
    /// `ServiceReorder` answers for both.
    func reorderSpace(
        droppedSpaceID: UUID,
        relativeTo targetSpaceID: UUID,
        placement: ServiceReorderPlacement
    ) throws -> Bool {
        let spaces = (try? context.fetch(
            FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []
        let live = spaces.filter { $0.modelContext != nil }
        let spacesByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })

        guard let reorderedIDs = ServiceReorder.reorderedIDs(
            live.map(\.id),
            moving: droppedSpaceID,
            relativeTo: targetSpaceID,
            placement: placement
        ) else { return false }

        let reordered = reorderedIDs.compactMap { spacesByID[$0] }
        guard reordered.count == reorderedIDs.count else { return false }
        for (index, space) in reordered.enumerated() {
            space.sortOrder = index
        }
        return context.saveOrRollback(reason: "reorder workspace")
    }

    func reorderService(
        droppedLinkID: UUID,
        relativeTo targetLinkID: UUID,
        placement: ServiceReorderPlacement
    ) throws -> Bool {
        let links = try liveLinks()
        guard let droppedLink = links.first(where: { $0.id == droppedLinkID }),
              let targetLink = links.first(where: { $0.id == targetLinkID }),
              WorkspaceNavigationPolicy.allowsReorder(
                  sourceWorkspaceID: droppedLink.space.id,
                  targetWorkspaceID: targetLink.space.id
              )
        else { return false }

        let spaceLinks = links
            .filter { $0.space.id == targetLink.space.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let linksByID = Dictionary(uniqueKeysWithValues: spaceLinks.map { ($0.id, $0) })
        guard let reorderedIDs = ServiceReorder.reorderedIDs(
            spaceLinks.map(\.id),
            moving: droppedLinkID,
            relativeTo: targetLinkID,
            placement: placement
        ) else { return false }

        let reorderedLinks = reorderedIDs.compactMap { linksByID[$0] }
        guard reorderedLinks.count == reorderedIDs.count else { return false }
        for (index, link) in reorderedLinks.enumerated() {
            link.sortOrder = index
        }
        return context.saveOrRollback(reason: "reorder service")
    }

    func deleteService(_ serviceID: UUID) throws -> ServiceDeletionOutcome? {
        guard let service = service(id: serviceID) else { return nil }
        let dataStoreIdentifier = service.dataStoreIdentifier
        context.delete(service)
        guard context.saveOrRollback(reason: "delete service") else { return nil }
        return ServiceDeletionOutcome(
            serviceID: serviceID,
            dataStoreIdentifier: dataStoreIdentifier
        )
    }

    func setServiceMuted(_ muted: Bool, for serviceID: UUID) throws -> Bool {
        guard let service = service(id: serviceID) else { return false }
        service.isMuted = muted
        return context.saveOrRollback(reason: "toggle service mute")
    }

    func setWorkspaceMuted(_ muted: Bool, for spaceID: UUID) throws -> Set<UUID>? {
        var descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceID })
        descriptor.fetchLimit = 1
        guard let space = try context.fetch(descriptor).first else { return nil }
        let serviceIDs = Set(
            try liveLinks()
                .filter { $0.space.id == spaceID }
                .map { $0.service.id }
        )
        space.isMuted = muted
        guard context.saveOrRollback(reason: "toggle workspace mute") else { return nil }
        return serviceIDs
    }

    func setCustomIconData(_ data: Data?, for serviceID: UUID) throws -> Bool {
        guard let service = service(id: serviceID) else { return false }
        service.customIconData = data
        return context.saveOrRollback(reason: "set custom icon")
    }

    func recordFetchedIconAttempt(
        _ data: Data?,
        at date: Date,
        for serviceID: UUID
    ) throws -> Bool {
        guard let service = service(id: serviceID), service.customIconData == nil else {
            return false
        }
        if let data {
            service.fetchedIconData = data
        }
        service.faviconFetchedAt = date
        return context.saveOrRollback(reason: "save fetched favicon")
    }

    func refreshFetchedIcon(for serviceID: UUID) async {
        guard let service = service(id: serviceID), service.customIconData == nil else { return }
        let serviceURL = service.url
        let data = await FaviconFetcher.shared.fetchFavicon(for: serviceURL)
        do {
            _ = try recordFetchedIconAttempt(data, at: Date(), for: serviceID)
        } catch {
            context.rollback()
            AppLogger.dataStore.error(
                "Failed to save fetched favicon; rolled back: \(error.localizedDescription)"
            )
        }
    }

    func serviceIDsNeedingFaviconRefresh(force: Bool, now: Date = Date()) -> [UUID] {
        let staleThreshold = now.addingTimeInterval(-7 * 24 * 60 * 60)
        return allServices().filter { service in
            guard service.customIconData == nil else { return false }
            if force { return true }
            guard let fetchedAt = service.faviconFetchedAt else { return true }
            return fetchedAt < staleThreshold
        }.map(\.id)
    }

    func removeLink(_ linkID: UUID) throws -> LinkRemovalOutcome? {
        let links = try liveLinks()
        guard let link = links.first(where: { $0.id == linkID }) else { return nil }
        let service = link.service
        let serviceID = service.id
        let dataStoreIdentifier = service.dataStoreIdentifier
        let hasOtherLinks = links.contains { $0.id != linkID && $0.service.id == serviceID }

        context.delete(link)
        if !hasOtherLinks {
            context.delete(service)
        }
        guard context.saveOrRollback(reason: "remove service link") else { return nil }
        return LinkRemovalOutcome(
            serviceID: serviceID,
            orphanedDataStoreIdentifier: hasOtherLinks ? nil : dataStoreIdentifier
        )
    }

    func deleteSpace(_ spaceID: UUID) throws -> SpaceDeletionOutcome? {
        var descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceID })
        descriptor.fetchLimit = 1
        guard let space = try context.fetch(descriptor).first else { return nil }

        let spaces = try context.fetch(
            FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        guard spaces.count > 1 else {
            AppLogger.dataStore.warning("Refusing to delete the last remaining space")
            return nil
        }
        let remainingSpaceID = spaces.first { $0.id != spaceID }?.id

        let links = try liveLinks()
        var linkedServices: [ServiceInstance] = []
        var seenServiceIDs: Set<UUID> = []
        for link in links where link.space.id == spaceID
            && seenServiceIDs.insert(link.service.id).inserted {
            linkedServices.append(link.service)
        }
        let orphanedIDs = WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: spaceID,
            memberships: Self.memberships(from: links)
        )
        let reclaimed = linkedServices.filter { orphanedIDs.contains($0.id) }
        let reclaimedServiceIDs = reclaimed.map(\.id)
        let orphanedDataStoreIdentifiers = reclaimed.map(\.dataStoreIdentifier)
        for service in reclaimed {
            context.delete(service)
        }
        context.delete(space)

        guard context.saveOrRollback(reason: "delete space \(spaceID)") else { return nil }
        AppLogger.dataStore.info(
            "Deleted space \(spaceID); reclaimed \(reclaimed.count) orphaned service(s)"
        )
        return SpaceDeletionOutcome(
            reclaimedServiceIDs: reclaimedServiceIDs,
            orphanedDataStoreIdentifiers: orphanedDataStoreIdentifiers,
            remainingSpaceID: remainingSpaceID
        )
    }

    func saveWindowSelection(spaceID: UUID?, serviceID: UUID?) {
        _ = preferencesStore.setWindowSelection(spaceID: spaceID, serviceID: serviceID)
    }

    func restoredWindowSelection(
        fallbackSpaceID: UUID?,
        fallbackServiceID: UUID?
    ) -> WindowSelection {
        let spaces = (try? context.fetch(
            FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []
        let existingSpaceIDs = Set(spaces.map(\.id))
        let spaceID: UUID?
        if let savedSpaceID = preferencesStore.selectedSpaceID,
           existingSpaceIDs.contains(savedSpaceID) {
            spaceID = savedSpaceID
        } else {
            spaceID = fallbackSpaceID.flatMap { existingSpaceIDs.contains($0) ? $0 : nil }
                ?? spaces.first?.id
        }

        guard let spaceID else { return WindowSelection(spaceID: nil, serviceID: nil) }
        let services = servicesForSpace(spaceID)
        let serviceID: UUID?
        if let savedServiceID = preferencesStore.selectedServiceID,
           services.contains(where: { $0.id == savedServiceID }) {
            serviceID = savedServiceID
        } else if let fallbackServiceID,
                  services.contains(where: { $0.id == fallbackServiceID }) {
            serviceID = fallbackServiceID
        } else {
            serviceID = services.first?.id
        }
        return WindowSelection(spaceID: spaceID, serviceID: serviceID)
    }

    func seedDefaultDataIfNeeded(defaults: UserDefaults = .standard) -> SeedOutcome {
        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        let existingSpaces: [Space]
        do {
            existingSpaces = try context.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error(
                "Failed to fetch spaces during seeding: \(error.localizedDescription)"
            )
            return SeedOutcome(didSeed: false, selectedSpaceID: nil)
        }

        guard existingSpaces.isEmpty else {
            return SeedOutcome(didSeed: false, selectedSpaceID: existingSpaces.first?.id)
        }
        guard !defaults.bool(forKey: DefaultsKey.hasEverHadData) else {
            AppLogger.dataStore.error(
                "Store is empty but this install has had data; skipping seed to avoid overwriting a lost store"
            )
            return SeedOutcome(didSeed: false, selectedSpaceID: nil)
        }

        let personalSpace = Space(
            name: DefaultSeed.spaces[0].name,
            emoji: DefaultSeed.spaces[0].emoji,
            sortOrder: 0
        )
        let workSpace = Space(
            name: DefaultSeed.spaces[1].name,
            emoji: DefaultSeed.spaces[1].emoji,
            sortOrder: 1
        )
        context.insert(personalSpace)
        context.insert(workSpace)

        for (index, entry) in DefaultSeed.personalServices.enumerated() {
            let service = ServiceInstance(
                label: entry.label,
                url: entry.url,
                catalogEntryID: entry.catalogID
            )
            context.insert(service)
            context.insert(
                SpaceServiceLink(sortOrder: index, space: personalSpace, service: service)
            )
        }
        for (index, entry) in DefaultSeed.workServices.enumerated() {
            let service = ServiceInstance(
                label: entry.label,
                url: entry.url,
                catalogEntryID: entry.catalogID
            )
            context.insert(service)
            context.insert(
                SpaceServiceLink(sortOrder: index, space: workSpace, service: service)
            )
        }

        guard context.saveOrRollback(reason: "seed default data") else {
            return SeedOutcome(didSeed: false, selectedSpaceID: nil)
        }
        StoreLoader.recordHasData(defaults)
        AppLogger.dataStore.info("Seeded default spaces: Personal and Work")
        return SeedOutcome(didSeed: true, selectedSpaceID: personalSpace.id)
    }

    func backfillPasskeyNoticeIfNeeded(
        freshInstall: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: DefaultsKey.passkeyNoticeBackfilled) else { return }
        defaults.set(true, forKey: DefaultsKey.passkeyNoticeBackfilled)
        guard !freshInstall else { return }

        let services = allServices()
        var changed = false
        for service in services where service.hasSeenPasskeyNotice == nil {
            service.hasSeenPasskeyNotice = true
            changed = true
        }
        guard changed else { return }
        if context.saveOrRollback(reason: "backfill passkey notice") {
            AppLogger.dataStore.info(
                "Backfilled passkey notice for \(services.count) existing service(s)"
            )
        }
    }

    func markPasskeyNoticeSeen(for serviceID: UUID) {
        guard let service = service(id: serviceID), service.needsPasskeyNotice else { return }
        service.hasSeenPasskeyNotice = true
        context.saveOrRollback(reason: "persist passkey notice dismissal")
    }
}
