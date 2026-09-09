import AppKit
import XCTest
import SwiftData
import BlattaCore
@testable import Blatta

@MainActor
final class ConfigurationTransferTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppPreferences.self, Space.self, ServiceInstance.self, SpaceServiceLink.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func fixture() -> ConfigurationArchive {
        var first = ConfigurationService()
        first.label = "Mail"
        first.url = "https://example.com/mail"
        first.customCSS = "body { opacity: 0.9; }"
        first.appearance = "dark"
        first.cameraPolicy = "deny"
        first.hibernationPolicy = "never"
        var second = ConfigurationService()
        second.label = "Chat"
        second.url = "https://example.com/chat"
        var personal = ConfigurationWorkspace()
        personal.name = "Personal"
        personal.emoji = "🏠"
        personal.isMuted = true
        personal.serviceIDs = [second.id, first.id]
        var work = ConfigurationWorkspace()
        work.name = "Work"
        work.serviceIDs = [first.id]
        var archive = ConfigurationArchive()
        archive.workspaces = [personal, work]
        archive.services = [first, second]
        archive.preferences.defaultZoom = 1.5
        archive.preferences.appearanceMode = "dark"
        return archive
    }

    func testImportPreservesOrderAndSharedAccountsWithFreshSessions() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        let existing = ServiceInstance(label: "Existing", url: "https://existing.example")
        let oldSession = existing.dataStoreIdentifier
        context.insert(existing)
        context.insert(Space(name: "Existing", sortOrder: 0))
        try context.save()
        let archive = fixture()
        _ = try store.importConfiguration(archive, applyPreferences: true)
        let spaces = try context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(spaces.map(\.name), ["Existing", "Personal", "Work"])
        let personal = store.servicesForSpace(spaces[1].id)
        let work = store.servicesForSpace(spaces[2].id)
        XCTAssertEqual(personal.map(\.label), ["Chat", "Mail"])
        XCTAssertEqual(personal[1].id, work[0].id)
        XCTAssertEqual(personal[1].webAppearance, .dark)
        XCTAssertEqual(personal[1].cameraPolicy, .deny)
        XCTAssertEqual(personal[1].customCSS, archive.services[0].customCSS)
        XCTAssertEqual(personal[1].hibernationPolicyEffective, .never)
        XCTAssertTrue(spaces[1].isMutedEffective)
        XCTAssertFalse(archive.services.map(\.id).contains(personal[1].id))
        XCTAssertNotEqual(personal[0].dataStoreIdentifier, personal[1].dataStoreIdentifier)
        XCTAssertEqual(existing.dataStoreIdentifier, oldSession)
        XCTAssertNil(personal[1].fetchedIconData)
        XCTAssertTrue(personal[1].needsPasskeyNotice)
        XCTAssertEqual(preferences.defaultZoom, 1.5)
        XCTAssertEqual(preferences.appearanceMode, .dark)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppPreferences>()), 1)
        let exported = try store.exportConfiguration()
        XCTAssertEqual(exported.workspaces[1].serviceIDs, personal.map(\.id))
        XCTAssertEqual(exported.workspaces[2].serviceIDs, [personal[1].id])
    }

    func testImportCanKeepPreferencesAndRepeatedImportsStayIndependent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        _ = try store.importConfiguration(fixture(), applyPreferences: false)
        _ = try store.importConfiguration(fixture(), applyPreferences: false)
        XCTAssertEqual(preferences.defaultZoom, 1)
        let services = store.allServices()
        XCTAssertEqual(services.count, 4)
        XCTAssertEqual(Set(services.map(\.dataStoreIdentifier)).count, 4)
    }

    func testFailedSaveRollsBackGraphAndPreferences() throws {
        enum Failure: Error { case save }
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        XCTAssertTrue(preferences.setDefaultZoom(1.25))
        XCTAssertThrowsError(try store.importConfiguration(fixture(), applyPreferences: true, save: { _ in throw Failure.save }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Space>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SpaceServiceLink>()), 0)
        XCTAssertEqual(preferences.defaultZoom, 1.25)
        let verification = ModelContext(container)
        XCTAssertEqual(try verification.fetch(FetchDescriptor<AppPreferences>()).first?.defaultZoom, 1.25)
    }

    func testPreferencesAndCustomIconRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        var archive = fixture()
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        archive.services[0].customIconData = try ServiceIconImageProcessor.normalizedPNG(from: image)
        archive.preferences.appPresenceMode = "menuBar"
        archive.preferences.showBadgeCountInDock = false
        archive.preferences.autoDismissCookieBanners = true
        archive.preferences.scheduledDNDEnabled = true
        archive.preferences.dndStartMinutes = 900
        archive.preferences.dndEndMinutes = 100
        archive.preferences.appLockEnabled = true
        archive.preferences.lockOnLaunch = false
        archive.preferences.lockOnSleep = false
        archive.preferences.railLayout = "servicesLeft"
        archive.preferences.contentBlockingEnabled = false
        archive.preferences.annoyanceBlockingEnabled = true
        archive.preferences.defaultCameraPolicy = "deny"
        archive.preferences.defaultMicrophonePolicy = "allow"
        archive.preferences.googleFaviconFallbackEnabled = true
        archive.preferences.autoHibernateIdleEnabled = true
        archive.preferences.autoHibernateIdleMinutes = 23
        _ = try store.importConfiguration(archive, applyPreferences: true)
        let exported = try store.exportConfiguration()
        XCTAssertEqual(exported.preferences, archive.preferences)
        let mail = try XCTUnwrap(exported.services.first { $0.label == "Mail" })
        let icon = try XCTUnwrap(mail.customIconData)
        XCTAssertNotNil(NSImage(data: icon))
        XCTAssertEqual(mail.cameraPolicy, "deny")
        XCTAssertEqual(mail.customCSS, archive.services[0].customCSS)
    }

    func testShellPreferencesPersistAcrossReload() throws {
        let suiteName = "ConfigurationTransferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try makeContainer()
        let preferences = PreferencesStore(context: container.mainContext)
        var shell = ShellPreferences.load(defaults: defaults, preferencesStore: preferences)
        var value = ConfigurationPreferences()
        value.liquidGlassStyle = "clear"
        value.liquidGlassIntensity = 0.4
        value.iconRailBaseSize = 30
        value.iconRailMagnification = 0.5
        value.iconRailPosition = "center"
        value.workspaceViewMode = "all"
        value.railBarIconsOnly = true
        value.sidebarCollapsed = true
        shell.applyConfiguration(value, defaults: defaults)
        let reloaded = ShellPreferences.load(defaults: defaults, preferencesStore: preferences)
        var exported = ConfigurationPreferences()
        reloaded.addToConfiguration(&exported)
        XCTAssertEqual(exported, value)
    }

    func testReplaceRemovesOldGraphAndReturnsSessionCleanupOnlyAfterSave() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        _ = try store.importConfiguration(fixture(), applyPreferences: false)
        let oldServices = store.allServices()
        let oldIDs = Set(oldServices.map(\.id))
        let oldSessionIDs = Set(oldServices.map(\.dataStoreIdentifier))
        let exported = try store.exportConfiguration()
        let outcome = try store.importConfiguration(exported, applyPreferences: false, mode: .replace)
        XCTAssertEqual(Set(outcome.removedServices.map(\.serviceID)), oldIDs)
        XCTAssertEqual(Set(outcome.removedServices.map(\.dataStoreIdentifier)), oldSessionIDs)
        XCTAssertEqual(Set(outcome.removedWorkspaceIDs), Set(exported.workspaces.map(\.id)))
        let spaces = try context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(spaces.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(spaces.map(\.sortOrder), [0, 1])
        XCTAssertEqual(outcome.firstWorkspaceID, spaces.first?.id)
        XCTAssertEqual(store.allServices().count, 2)
        XCTAssertTrue(Set(store.allServices().map(\.id)).isDisjoint(with: oldIDs))
        XCTAssertTrue(Set(store.allServices().map(\.dataStoreIdentifier)).isDisjoint(with: oldSessionIDs))
        XCTAssertEqual(try store.liveLinks().count, 3)
        XCTAssertEqual(store.servicesForSpace(spaces[0].id)[1].id,
                       store.servicesForSpace(spaces[1].id)[0].id)
    }

    func testFailedReplacementRestoresExistingGraphAndPreferences() throws {
        enum Failure: Error { case save }
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        _ = try store.importConfiguration(fixture(), applyPreferences: false)
        let before = try store.exportConfiguration()
        let sessions = Set(store.allServices().map(\.dataStoreIdentifier))
        XCTAssertThrowsError(try store.importConfiguration(fixture(), applyPreferences: true,
                                                          mode: .replace, save: { _ in throw Failure.save }))
        XCTAssertEqual(try store.exportConfiguration(), before)
        XCTAssertEqual(Set(store.allServices().map(\.dataStoreIdentifier)), sessions)
        let verification = ModelContext(container)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<ServiceInstance>()), 2)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<SpaceServiceLink>()), 3)
    }

    func testEmptyReplacementClearsGraphAndKeepsPreferencesWhenUnchecked() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        _ = try store.importConfiguration(fixture(), applyPreferences: true)
        let outcome = try store.importConfiguration(ConfigurationArchive(), applyPreferences: false, mode: .replace)
        XCTAssertNil(outcome.firstWorkspaceID)
        XCTAssertEqual(outcome.removedServices.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Space>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SpaceServiceLink>()), 0)
        XCTAssertEqual(preferences.defaultZoom, 1.5)
    }

    func testInvalidIconAndReferencesDoNotChangeTheStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        var archive = fixture()
        archive.services[0].customIconData = Data("not an image".utf8)
        XCTAssertThrowsError(try store.importConfiguration(archive, applyPreferences: true))
        archive = fixture()
        archive.workspaces[0].serviceIDs = [UUID()]
        XCTAssertThrowsError(try store.importConfiguration(archive, applyPreferences: true))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(preferences.defaultZoom, 1)
    }
}
