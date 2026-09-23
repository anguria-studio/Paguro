import Foundation
import SwiftData
import PaguroCore

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

    func liveLinks() throws -> [LiveSpaceServiceLink] {
        try context.fetch(FetchDescriptor<SpaceServiceLink>())
            .compactMap(LiveSpaceServiceLink.init)
    }

    static func memberships(from links: [LiveSpaceServiceLink]) -> [UUID: Set<UUID>] {
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
        fetchedIconData: Data? = nil,
        to spaceID: UUID?,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> UUID? {
        try addServices([
            ServiceSetupDraft(
                label: label, url: url, catalogEntryID: catalogEntryID,
                userAgent: userAgent, customIconData: customIconData,
                fetchedIconData: fetchedIconData
            )
        ], to: spaceID, save: save)?.first
    }

    /// Commits the whole selection, including Home, or rolls everything back.
    func addServices(
        _ drafts: [ServiceSetupDraft],
        to spaceID: UUID?,
        workspaceName: String? = nil,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> [UUID]? {
        guard !drafts.isEmpty else { return [] }
        let normalizedName = workspaceName.flatMap(WorkspaceName.normalized)
        guard workspaceName == nil || normalizedName != nil else { return nil }
        let spaces = try context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)]))
        let links = try liveLinks()
        let space: Space
        if let spaceID {
            guard let target = spaces.first(where: { $0.id == spaceID }) else { return nil }
            space = target
        } else if let existing = spaces.first {
            space = existing
        } else {
            // The workspace and services commit together, so cancel leaves no workspace.
            space = Space(name: normalizedName ?? WorkspaceName.defaultValue, emoji: "", sortOrder: 0)
            context.insert(space)
        }
        if let normalizedName { space.name = normalizedName }
        let nextOrder = (links
            .filter { $0.space.id == space.id }
            .map(\.sortOrder)
            .max() ?? -1) + 1

        let serviceIDs = drafts.enumerated().map { offset, draft in
            let service = ServiceInstance(
                label: draft.label, url: draft.url,
                customIconData: draft.customIconData,
                catalogEntryID: draft.catalogEntryID, userAgent: draft.userAgent
            )
            context.insert(service)
            if let icon = draft.fetchedIconData {
                service.fetchedIconData = icon
                service.faviconFetchedAt = Date()
            }
            context.insert(SpaceServiceLink(
                sortOrder: nextOrder + offset, space: space, service: service
            ))
            return service.id
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
        return serviceIDs
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
        link.link.sortOrder = (targetOrders.max() ?? -1) + 1
        link.link.space = targetSpace
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
            link.link.sortOrder = index
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

        if hasOtherLinks {
            context.delete(link.link)
        } else {
            // The service cascade removes its last membership. Deleting that
            // link first can leave SwiftData inspecting an invalidated child.
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


}

extension WorkspaceStore {
    /// Uses configured URLs and custom icons only, never live pages or browser storage.
    func exportConfiguration() throws -> ConfigurationArchive {
        var archive = ConfigurationArchive()
        let services = try context.fetch(FetchDescriptor<ServiceInstance>())
        let spaces = try context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)]))
        let links = try liveLinks()
        archive.workspaces = spaces.map { space in
            var item = ConfigurationWorkspace()
            item.id = space.id
            item.name = space.name
            item.emoji = space.emoji
            item.isMuted = space.isMutedEffective
            item.serviceIDs = links.filter { $0.space.id == space.id }
                .sorted { $0.sortOrder < $1.sortOrder }.map(\.service.id)
            return item
        }
        archive.services = services.sorted { $0.id.uuidString < $1.id.uuidString }.map { service in
            var item = ConfigurationService()
            item.id = service.id
            item.label = service.label
            item.url = service.url
            item.customIconData = service.customIconData
            item.catalogEntryID = service.catalogEntryID
            item.isMuted = service.isMuted
            item.showBadge = service.showBadge
            item.userAgent = service.userAgent
            item.pageZoom = service.pageZoom
            item.osNotificationsEnabled = service.notifiesOSEffective
            item.customCSS = service.customCSS
            item.appearance = service.webAppearance.rawValue
            item.cameraPolicy = service.cameraPolicyRaw
            item.microphonePolicy = service.microphonePolicyRaw
            item.openExternalLinksInApp = service.opensExternalLinksInAppEffective
            item.followsGlobalLinkOpening = service.openExternalLinksInApp == nil
            item.stayActiveInBackground = service.staysActiveInBackgroundEffective
            item.hibernationPolicy = service.hibernationPolicyEffective.rawValue
            item.hibernateAfterMinutes = service.hibernateAfterMinutesEffective
            return item
        }
        archive.preferences = preferencesStore.configurationPreferences()
        return archive
    }

    struct ConfigurationImportOutcome {
        let firstWorkspaceID: UUID?
        let removedWorkspaceIDs: [UUID]
        let removedServices: [ServiceDeletionOutcome]
    }

    /// Adds fresh accounts. IDs in the file are only references within that file.
    /// A single save commits the graph and optional preferences together.
    func importConfiguration(
        _ archive: ConfigurationArchive,
        applyPreferences: Bool,
        mode: ConfigurationImportMode = .add,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ConfigurationImportOutcome {
        try ConfigurationArchiveCodec.validate(archive)
        var icons: [UUID: Data] = [:]
        for item in archive.services {
            if let data = item.customIconData {
                icons[item.id] = try ServiceIconImageProcessor.normalizedPNG(from: data)
            }
        }
        let existing = try context.fetch(FetchDescriptor<Space>())
        let replacedServices = mode == .replace
            ? try context.fetch(FetchDescriptor<ServiceInstance>()) : []
        let replacedLinks = mode == .replace
            ? try context.fetch(FetchDescriptor<SpaceServiceLink>()) : []
        let removedWorkspaceIDs = mode == .replace ? existing.map(\.id) : []
        let removedServices = replacedServices.map {
            ServiceDeletionOutcome(serviceID: $0.id, dataStoreIdentifier: $0.dataStoreIdentifier)
        }
        let startOrder = mode == .replace ? 0 : (existing.map(\.sortOrder).max() ?? -1) + 1
        // Establish a rollback baseline for a preferences row created at launch.
        try context.save()
        let previousPreferences = preferencesStore.configurationPreferences()
        do {
            if mode == .replace {
                for link in replacedLinks { context.delete(link) }
                for space in existing { context.delete(space) }
                for service in replacedServices { context.delete(service) }
            }
            var services: [UUID: ServiceInstance] = [:]
            for item in archive.services {
                let service = ServiceInstance(
                    label: item.label, url: item.url, customIconData: icons[item.id],
                    catalogEntryID: item.catalogEntryID, isMuted: item.isMuted,
                    showBadge: item.showBadge, userAgent: item.userAgent,
                    pageZoom: item.pageZoom, osNotificationsEnabled: item.osNotificationsEnabled,
                    customCSS: item.customCSS, darkModeRaw: item.appearance,
                    cameraPolicyRaw: item.cameraPolicy, microphonePolicyRaw: item.microphonePolicy,
                    openExternalLinksInApp: item.followsGlobalLinkOpening == true ? nil : item.openExternalLinksInApp,
                    stayActiveInBackground: item.stayActiveInBackground,
                    hibernationPolicyRaw: item.hibernationPolicy,
                    hibernateAfterMinutes: item.hibernateAfterMinutes
                )
                context.insert(service)
                services[item.id] = service
            }
            var firstWorkspaceID: UUID?
            for (index, item) in archive.workspaces.enumerated() {
                let space = Space(name: item.name, emoji: item.emoji,
                                  sortOrder: startOrder + index, isMuted: item.isMuted)
                context.insert(space)
                if firstWorkspaceID == nil { firstWorkspaceID = space.id }
                for (order, id) in item.serviceIDs.enumerated() {
                    guard let service = services[id] else { continue }
                    context.insert(SpaceServiceLink(sortOrder: order, space: space, service: service))
                }
            }
            if applyPreferences { preferencesStore.stageConfiguration(archive.preferences) }
            context.processPendingChanges()
            try save(context)
            return ConfigurationImportOutcome(
                firstWorkspaceID: firstWorkspaceID,
                removedWorkspaceIDs: removedWorkspaceIDs,
                removedServices: removedServices
            )
        } catch {
            context.rollback()
            // SwiftData can keep updated values in the retained preferences object.
            // Restore the portable snapshot as well as rolling back the graph.
            if applyPreferences { preferencesStore.stageConfiguration(previousPreferences) }
            throw error
        }
    }
}
