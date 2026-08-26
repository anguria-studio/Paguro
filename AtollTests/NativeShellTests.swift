import XCTest
import SwiftData
@testable import Atoll

final class NativeShellTests: XCTestCase {
    // MARK: - Notice shape, radius scale, selection against focus (build step 7)

    /// Eight radii down to three. The point of the scale is that there is
    /// nowhere else to go, so a fourth value is the thing the test catches.
    func testRadiusScaleHasExactlyThreeValues() {
        XCTAssertEqual(Set(AtollRadius.allValues), [4, 8, 14])
        XCTAssertEqual(AtollRadius.icon, 4)
        XCTAssertEqual(AtollRadius.control, 8)
        XCTAssertEqual(AtollRadius.surface, 14)
    }

    /// The shell uses the compact system type ramp from the two reference apps.
    /// These values must change as one reviewed group.
    func testMainWindowTypeRampMatchesTheReferenceApps() {
        XCTAssertEqual(Set(AtollTypeSize.allValues), [10.5, 11, 12, 12.5, 13, 14])
        XCTAssertEqual(AtollTypeSize.sidebarLabel, 13)
        XCTAssertEqual(AtollTypeSize.sidebarSection, 11)
        XCTAssertEqual(AtollTypeSize.toolbarControl, 12)
        XCTAssertEqual(AtollTypeSize.toolbarTitle, 14)
    }

    func testGlassIntensityScaleClampsAndRevealsTheBackdrop() {
        XCTAssertEqual(GlassIntensityScale.normalized(-1), 0)
        XCTAssertEqual(GlassIntensityScale.normalized(0.5), 0.5)
        XCTAssertEqual(GlassIntensityScale.normalized(2), 1)
        XCTAssertGreaterThan(
            GlassIntensityScale.shellOpacity(0),
            GlassIntensityScale.shellOpacity(1)
        )
        XCTAssertGreaterThan(
            GlassIntensityScale.controlTintAlpha(0),
            GlassIntensityScale.controlTintAlpha(1)
        )
        XCTAssertEqual(GlassIntensityScale.shellOpacity(0), 1, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.shellOpacity(0.5), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.shellOpacity(1), 0, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.surfaceOpacity(0), 0.08, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.surfaceOpacity(1), 0, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.sidebarOpacity(0), 0.12, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.sidebarOpacity(1), 0, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.materialTintOpacity(1), 0, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.adaptiveSelectionProgress(0.6), 0, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.adaptiveSelectionProgress(0.8), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(GlassIntensityScale.adaptiveSelectionProgress(1), 1, accuracy: 0.000_001)
    }

    func testGlassLabUsesThreeExplicitNativeStyleChoices() {
        XCTAssertEqual(
            ShellGlassStyle.allCases.map(\.rawValue),
            ["off", "clear", "regular"]
        )
        XCTAssertEqual(ShellGlassStyle.resolving("regular"), .regular)
        XCTAssertEqual(ShellGlassStyle.resolving("unsupported"), .regular)
        XCTAssertEqual(ShellGlassStyle.resolving(nil), .regular)
        XCTAssertEqual(GlassLabDefaults.style, .regular)
        XCTAssertEqual(GlassLabDefaults.transparency, 1)
        XCTAssertEqual(GlassLabDefaults.regularFrost, 1)
        XCTAssertEqual(ShellGlassStyle.off.frostOpacity, 1)
        XCTAssertEqual(ShellGlassStyle.clear.frostOpacity, 0.7)
        XCTAssertEqual(ShellGlassStyle.regular.frostOpacity, 1)
    }

    func testReviewedSettingsAreTheFreshInstallDefaults() {
        let preferences = AppPreferences()

        XCTAssertEqual(preferences.appPresenceMode, .both)
        XCTAssertTrue(preferences.showBadgeCountInDock)
        XCTAssertFalse(preferences.autoDismissCookieBanners)
        XCTAssertEqual(DockRailPosition.defaultPosition, .top)
    }

    /// Both rail forms derive from one reviewed source-list geometry rule.
    func testNativeSidebarGeometryIsInternallyConsistent() {
        XCTAssertEqual(AtollMetric.Sidebar.surfaceWidth, 218)
        XCTAssertEqual(AtollMetric.Sidebar.expandedWidth, 234)
        XCTAssertEqual(AtollMetric.Sidebar.collapsedWidth, 62)
        XCTAssertEqual(AtollMetric.Sidebar.contentInset, 10)
        XCTAssertEqual(AtollMetric.Sidebar.horizontalInset, 18)
        XCTAssertEqual(AtollMetric.Sidebar.rowWidth, 198)
        XCTAssertEqual(
            AtollMetric.Sidebar.rowWidth + (AtollMetric.Sidebar.contentInset * 2),
            AtollMetric.Sidebar.surfaceWidth
        )
        XCTAssertEqual(AtollMetric.Sidebar.rowHeight, 28)
        XCTAssertEqual(AtollMetric.Sidebar.dockItemSize, 36)
        XCTAssertEqual(AtollMetric.Sidebar.dockRowHeight, 44)
        XCTAssertEqual(AtollMetric.Sidebar.collapsedIconSize, 22)
        XCTAssertEqual(
            AtollMetric.Sidebar.collapsedWidth
                - (AtollMetric.Sidebar.surfaceInset * 2)
                - AtollMetric.Sidebar.dockItemSize,
            10
        )
        XCTAssertEqual(AtollMetric.Sidebar.rowRadius, 7)
        XCTAssertEqual(AtollMetric.Sidebar.surfaceInset, 8)
        XCTAssertEqual(AtollMetric.Sidebar.topBarHeight, 52)
        XCTAssertEqual(AtollMetric.Sidebar.collapsedSurfaceTopInset, 52)
        XCTAssertEqual(AtollMetric.Sidebar.collapsedContentTopInset, 60)
        XCTAssertEqual(AtollMetric.Sidebar.expandedToggleTrailingInset, 14)
        XCTAssertEqual(AtollMetric.Sidebar.footerHeight, 52)
        XCTAssertEqual(AtollMetric.Sidebar.workspaceDividerHorizontalInset, 15)
        XCTAssertEqual(AtollMetric.Toolbar.height, 52)
        XCTAssertEqual(AtollMetric.Toolbar.controlSize, 28)
        XCTAssertEqual(AtollMetric.Toolbar.sidebarToggleSize, 32)
        XCTAssertEqual(AtollMetric.Toolbar.glyphSize, 14)
        XCTAssertEqual(AtollMetric.Toolbar.sidebarGlyphSize, 16)
        XCTAssertEqual(AtollMetric.Toolbar.horizontalInset, 8)
        XCTAssertEqual(AtollMetric.Toolbar.trafficLightTrailingEdge, 79)
        XCTAssertEqual(AtollMetric.Toolbar.trafficLightClearance, 16)
        XCTAssertEqual(AtollMetric.Toolbar.collapsedLeadingInset, 33)
        XCTAssertEqual(
            AtollMetric.Sidebar.collapsedWidth
                + AtollMetric.Toolbar.collapsedLeadingInset
                - AtollMetric.Toolbar.trafficLightTrailingEdge,
            AtollMetric.Toolbar.trafficLightClearance
        )
    }

    func testSidebarPresentationMapsToReviewedGeometry() {
        XCTAssertEqual(SidebarPresentation.expanded.width, 234)
        XCTAssertEqual(SidebarPresentation.expanded.serviceRowHeight, 28)
        XCTAssertEqual(SidebarPresentation.expanded.surfaceTopInset, 8)
        XCTAssertEqual(SidebarPresentation.expanded.surfaceBottomInset, 8)
        XCTAssertEqual(SidebarPresentation.expanded.contentTopInset, 52)
        XCTAssertEqual(SidebarPresentation.expanded.toggleCenterX, 204)
        XCTAssertTrue(SidebarPresentation.expanded.showsLabels)

        XCTAssertEqual(SidebarPresentation.collapsed.width, 62)
        XCTAssertEqual(SidebarPresentation.collapsed.serviceRowHeight, 44)
        XCTAssertEqual(SidebarPresentation.collapsed.surfaceTopInset, 52)
        XCTAssertEqual(SidebarPresentation.collapsed.surfaceBottomInset, 8)
        XCTAssertEqual(SidebarPresentation.collapsed.contentTopInset, 60)
        XCTAssertEqual(SidebarPresentation.collapsed.toggleCenterX, 111)
        XCTAssertFalse(SidebarPresentation.collapsed.showsLabels)
    }

    /// Three severities, and the tone has to carry the difference: same fill
    /// weight throughout, a different tint and a different icon per severity.
    func testNoticeSeveritiesAreDistinctInToneAndIcon() {
        let all = NoticeSeverity.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.systemImage)).count, 3)
        // One fill weight for all three: the spec's point is that the fill does
        // not carry severity, the icon and the rule do.
        XCTAssertEqual(Set(all.map(\.fillOpacity)).count, 1)
    }

    /// A selected row needs only its fill. A ring appears when keyboard focus is
    /// on another row, where it gives information that selection does not.
    func testSelectionAndFocusNeverDrawTheSameMark() {
        XCTAssertEqual(RowMark(isSelected: true, isFocused: false), RowMark(fill: .selected, ring: false))
        XCTAssertEqual(RowMark(isSelected: false, isFocused: true), RowMark(fill: .none, ring: true))
        XCTAssertEqual(RowMark(isSelected: true, isFocused: true), RowMark(fill: .selected, ring: false))
        XCTAssertEqual(RowMark(isSelected: false, isFocused: false), RowMark(fill: .none, ring: false))
    }

    /// Hover is a third, quieter thing, and selection outranks it — a selected
    /// row under the pointer should not change weight.
    func testHoverIsOutrankedBySelection() {
        XCTAssertEqual(RowMark(isSelected: false, isFocused: false, isHovering: true).fill, .hover)
        XCTAssertEqual(RowMark(isSelected: true, isFocused: false, isHovering: true).fill, .selected)
    }

    // MARK: - Service health (build step 6)

    /// A load starting always means loading, including a retry after a failure —
    /// otherwise the orange dot would sit there through a successful reload.
    func testServiceHealthStartingALoadAlwaysMeansLoading() {
        XCTAssertEqual(ServiceHealth.live.next(.startedLoading), .loading)
        XCTAssertEqual(ServiceHealth.failed.next(.startedLoading), .loading)
        XCTAssertEqual(ServiceHealth.loading.next(.startedLoading), .loading)
    }

    func testServiceHealthFinishingALoadClearsBothLoadingAndFailed() {
        XCTAssertEqual(ServiceHealth.loading.next(.finishedLoading), .live)
        XCTAssertEqual(ServiceHealth.failed.next(.finishedLoading), .live)
        XCTAssertEqual(ServiceHealth.live.next(.finishedLoading), .live)
    }

    func testServiceHealthFailureWins() {
        XCTAssertEqual(ServiceHealth.loading.next(.failed), .failed)
        XCTAssertEqual(ServiceHealth.live.next(.failed), .failed)
    }

    /// Signed-out detection is deliberately not built (there is no general signal
    /// for it — see the spec). The case exists so the rail can draw it, but no
    /// navigation event may ever produce it, and nothing should quietly start.
    func testNoNavigationEventEverProducesSignedOut() {
        for start in [ServiceHealth.live, .loading, .failed, .signedOut] {
            for event in ServiceHealth.Event.allCases {
                XCTAssertNotEqual(start.next(event), .signedOut, "\(start) + \(event) produced signedOut")
            }
        }
    }

    /// Only `live` draws nothing. The other three each need a mark, and each mark
    /// needs a shape of its own — colour alone fails a red-green colour-blind
    /// user, which is the app's own standard.
    func testOnlyLiveDrawsNoDotAndEveryOtherStateHasItsOwnShape() {
        XCTAssertFalse(ServiceHealth.live.drawsDot)
        XCTAssertTrue(ServiceHealth.loading.drawsDot)
        XCTAssertTrue(ServiceHealth.failed.drawsDot)
        XCTAssertTrue(ServiceHealth.signedOut.drawsDot)

        let shapes = [ServiceHealth.loading, .failed, .signedOut].map(\.dotShape)
        XCTAssertEqual(Set(shapes).count, 3, "two health states share a silhouette")
    }

    /// The state has to reach VoiceOver in words, not only as a coloured dot.
    func testSpokenLabelCarriesHealthInWords() {
        XCTAssertEqual(
            ServiceAccessibility.label(name: "Slack", badgeCount: 0, isHibernated: false, isMuted: false, health: .live),
            "Slack"
        )
        XCTAssertEqual(
            ServiceAccessibility.label(name: "Slack", badgeCount: 0, isHibernated: false, isMuted: false, health: .loading),
            "Slack, loading"
        )
        XCTAssertEqual(
            ServiceAccessibility.label(name: "Slack", badgeCount: 3, isHibernated: false, isMuted: false, health: .failed),
            "Slack, 3 unread, failed to load"
        )
        XCTAssertEqual(
            ServiceAccessibility.label(name: "Slack", badgeCount: 0, isHibernated: false, isMuted: true, health: .signedOut),
            "Slack, muted, signed out"
        )
    }

    // MARK: - Space header and palette (build step 4)

    /// The palette labels its rows ⌘1 upward. Only the first nine get a digit —
    /// there is no ⌘0 row, and a tenth space is reached by arrow or click.
    func testSpacePaletteAssignsCommandDigitsToTheFirstNineRowsOnly() {
        XCTAssertEqual(SpacePalette.shortcutDigit(forIndex: 0), 1)
        XCTAssertEqual(SpacePalette.shortcutDigit(forIndex: 8), 9)
        XCTAssertNil(SpacePalette.shortcutDigit(forIndex: 9))
        XCTAssertNil(SpacePalette.shortcutDigit(forIndex: 40))
    }

    /// The digits are palette-local (decided 2026-08-17): they resolve to a row
    /// only while the palette is open, and only when a row is actually there. A
    /// digit past the end is not handled, so it never swallows the keystroke.
    func testSpacePaletteResolvesADigitOnlyWithinTheRowCount() {
        XCTAssertEqual(SpacePalette.index(forDigit: 1, rowCount: 3), 0)
        XCTAssertEqual(SpacePalette.index(forDigit: 3, rowCount: 3), 2)
        XCTAssertNil(SpacePalette.index(forDigit: 4, rowCount: 3))
        XCTAssertNil(SpacePalette.index(forDigit: 0, rowCount: 3))
        XCTAssertNil(SpacePalette.index(forDigit: 10, rowCount: 12))
        XCTAssertNil(SpacePalette.index(forDigit: 1, rowCount: 0))
    }

    func testSpacePaletteSubtitleCountsServices() {
        XCTAssertEqual(SpacePalette.subtitle(serviceCount: 0), "No services")
        XCTAssertEqual(SpacePalette.subtitle(serviceCount: 1), "1 service")
        XCTAssertEqual(SpacePalette.subtitle(serviceCount: 4), "4 services")
    }

    /// VoiceOver hears everything the row shows: name, how many services, the
    /// unread count, and mute. Mirrors `ServiceAccessibility.label`.
    func testSpacePaletteRowSpokenLabelFoldsInCountBadgeAndMute() {
        XCTAssertEqual(
            SpacePalette.rowLabel(name: "Work", serviceCount: 3, badgeCount: 0, isMuted: false),
            "Work, 3 services"
        )
        XCTAssertEqual(
            SpacePalette.rowLabel(name: "Work", serviceCount: 1, badgeCount: 1, isMuted: false),
            "Work, 1 service, 1 unread"
        )
        XCTAssertEqual(
            SpacePalette.rowLabel(name: "Work", serviceCount: 2, badgeCount: 7, isMuted: true),
            "Work, 2 services, 7 unread, muted"
        )
    }

    /// The header says where you are and that it opens something. The trait is
    /// applied by the view; this pins the words.
    func testSpaceHeaderSpokenLabelFoldsInBadgeAndMute() {
        XCTAssertEqual(SpaceHeader.label(spaceName: "Work", badgeCount: 0, isMuted: false), "Work")
        XCTAssertEqual(SpaceHeader.label(spaceName: "Work", badgeCount: 1, isMuted: false), "Work, 1 unread")
        XCTAssertEqual(SpaceHeader.label(spaceName: "Work", badgeCount: 12, isMuted: true), "Work, 12 unread, muted")
    }

    /// With no space resolved the header still draws rather than collapsing the
    /// rail, and it says so.
    func testSpaceHeaderLabelWithoutASpace() {
        XCTAssertEqual(SpaceHeader.label(spaceName: nil, badgeCount: 0, isMuted: false), "No space")
    }

    func testWorkspaceSectionLabelDescribesDisclosureAndHiddenBadge() {
        XCTAssertEqual(
            WorkspaceSectionHeader.label(
                workspaceName: "Work",
                badgeCount: 0,
                isMuted: false,
                isExpanded: true
            ),
            "Work, expanded"
        )
        XCTAssertEqual(
            WorkspaceSectionHeader.label(
                workspaceName: "Work",
                badgeCount: 12,
                isMuted: true,
                isExpanded: false
            ),
            "Work, 12 unread, muted, collapsed"
        )
    }

    func testDuplicateServiceLabelAddsItsWorkspaceContext() {
        XCTAssertEqual(
            ServiceRowLabel.contextualName(
                serviceName: "Gmail",
                workspaceName: nil
            ),
            "Gmail"
        )
        XCTAssertEqual(
            ServiceRowLabel.contextualName(
                serviceName: "Gmail",
                workspaceName: "Personal"
            ),
            "Gmail — Personal"
        )
    }

    func testAppearanceModeParsesFromStoredValueWithSystemFallback() {
        XCTAssertEqual(AppPreferences(appearanceModeRaw: nil).appearanceMode, .system)
        XCTAssertEqual(AppPreferences(appearanceModeRaw: "system").appearanceMode, .system)
        XCTAssertEqual(AppPreferences(appearanceModeRaw: "light").appearanceMode, .light)
        XCTAssertEqual(AppPreferences(appearanceModeRaw: "dark").appearanceMode, .dark)
        XCTAssertEqual(AppPreferences(appearanceModeRaw: "garbage").appearanceMode, .system)
    }

    // MARK: - Notification grouping by space

    @MainActor
    func testNotificationGroupingIsFlatAndHeaderlessWhenNoSpacesHaveMembers() throws {
        let container = try ModelFixtures.groupingContainer()
        let ctx = container.mainContext
        let a = ServiceInstance(label: "Zulip", url: "https://z.example")
        let b = ServiceInstance(label: "Asana", url: "https://a.example")
        let empty = Space(name: "Empty", emoji: "📭", sortOrder: 0)
        [a, b].forEach(ctx.insert)
        ctx.insert(empty)
        try ctx.save()

        let result = NotificationGrouping.grouped(spaces: [empty], services: [a, b])

        XCTAssertFalse(result.showsHeaders)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertNil(result.groups[0].space)
        // Flat bucket is sorted by label.
        XCTAssertEqual(result.groups[0].services.map(\.label), ["Asana", "Zulip"])
    }

    @MainActor
    func testNotificationGroupingFollowsSpaceOrderThenLinkOrder() throws {
        let container = try ModelFixtures.groupingContainer()
        let ctx = container.mainContext
        let work = Space(name: "Work", emoji: "🏢", sortOrder: 0)
        let play = Space(name: "Play", emoji: "🎮", sortOrder: 1)
        let slack = ServiceInstance(label: "Slack", url: "https://s.example")
        let gmail = ServiceInstance(label: "Gmail", url: "https://g.example")
        let discord = ServiceInstance(label: "Discord", url: "https://d.example")
        [work, play].forEach(ctx.insert)
        [slack, gmail, discord].forEach(ctx.insert)
        // Add gmail first but at a higher sortOrder to prove link order wins.
        ModelFixtures.link(gmail, to: work, sortOrder: 1, in: ctx)
        ModelFixtures.link(slack, to: work, sortOrder: 0, in: ctx)
        ModelFixtures.link(discord, to: play, sortOrder: 0, in: ctx)
        try ctx.save()

        let result = NotificationGrouping.grouped(spaces: [work, play], services: [slack, gmail, discord])

        XCTAssertTrue(result.showsHeaders)
        XCTAssertEqual(result.groups.map { $0.space?.name }, ["Work", "Play"])
        XCTAssertEqual(result.groups[0].services.map(\.label), ["Slack", "Gmail"])
        XCTAssertEqual(result.groups[1].services.map(\.label), ["Discord"])
    }

    @MainActor
    func testNotificationGroupingPutsUngroupedServicesInTrailingBucket() throws {
        let container = try ModelFixtures.groupingContainer()
        let ctx = container.mainContext
        let work = Space(name: "Work", emoji: "🏢", sortOrder: 0)
        let slack = ServiceInstance(label: "Slack", url: "https://s.example")
        let loose2 = ServiceInstance(label: "Notion", url: "https://n.example")
        let loose1 = ServiceInstance(label: "Figma", url: "https://f.example")
        ctx.insert(work)
        [slack, loose2, loose1].forEach(ctx.insert)
        ModelFixtures.link(slack, to: work, sortOrder: 0, in: ctx)
        try ctx.save()

        let result = NotificationGrouping.grouped(spaces: [work], services: [slack, loose2, loose1])

        XCTAssertTrue(result.showsHeaders)
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups[0].space?.name, "Work")
        XCTAssertNil(result.groups[1].space)  // the ungrouped bucket, last
        XCTAssertEqual(result.groups[1].services.map(\.label), ["Figma", "Notion"])
    }

    @MainActor
    func testNotificationGroupingSkipsSpacesWithNoServices() throws {
        let container = try ModelFixtures.groupingContainer()
        let ctx = container.mainContext
        let full = Space(name: "Full", emoji: "📥", sortOrder: 0)
        let empty = Space(name: "Empty", emoji: "📭", sortOrder: 1)
        let slack = ServiceInstance(label: "Slack", url: "https://s.example")
        [full, empty].forEach(ctx.insert)
        ctx.insert(slack)
        ModelFixtures.link(slack, to: full, sortOrder: 0, in: ctx)
        try ctx.save()

        let result = NotificationGrouping.grouped(spaces: [full, empty], services: [slack])

        XCTAssertEqual(result.groups.map { $0.space?.name }, ["Full"])
    }

    @MainActor
    func testNotificationGroupingRepeatsServiceInEachSpace() throws {
        let container = try ModelFixtures.groupingContainer()
        let ctx = container.mainContext
        let home = Space(name: "Home", emoji: "🏠", sortOrder: 0)
        let design = Space(name: "Design", emoji: "🎨", sortOrder: 1)
        let slack = ServiceInstance(label: "Slack", url: "https://s.example")
        [home, design].forEach(ctx.insert)
        ctx.insert(slack)
        ModelFixtures.link(slack, to: home, sortOrder: 0, in: ctx)
        ModelFixtures.link(slack, to: design, sortOrder: 0, in: ctx)
        try ctx.save()

        let result = NotificationGrouping.grouped(spaces: [home, design], services: [slack])

        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups[0].services.map(\.label), ["Slack"])
        XCTAssertEqual(result.groups[1].services.map(\.label), ["Slack"])
        // Same underlying object under both headers, so toggles stay in sync.
        XCTAssertTrue(result.groups[0].services[0] === result.groups[1].services[0])
        // No ungrouped bucket when every service belongs to a space.
        XCTAssertFalse(result.groups.contains { $0.space == nil })
    }

    /// Exercises the dangling-link guard: a link whose service has no
    /// `modelContext` (a deleted or never-inserted model — the crash class the
    /// guard exists for) must be skipped, not grouped or trapped on.
    @MainActor
    func testNotificationGroupingSkipsLinkWhoseServiceIsDetached() throws {
        // A live space with a real, inserted, linked service.
        let container = try ModelFixtures.groupingContainer()
        let ctx = container.mainContext
        let live = Space(name: "Live", emoji: "✅", sortOrder: 0)
        let alpha = ServiceInstance(label: "Alpha", url: "https://a.example")
        ctx.insert(live)
        ctx.insert(alpha)
        ModelFixtures.link(alpha, to: live, sortOrder: 0, in: ctx)
        try ctx.save()

        // A detached space whose link points at a never-inserted service — the
        // stand-in for a dangling link. Its service has a nil modelContext, so
        // the guard must skip it rather than group it.
        let ghost = Space(name: "Ghost", emoji: "👻", sortOrder: 1)
        let beta = ServiceInstance(label: "Beta", url: "https://b.example")
        let danglingLink = SpaceServiceLink(sortOrder: 0, space: ghost, service: beta)
        ghost.serviceLinks.append(danglingLink)
        beta.spaceLinks.append(danglingLink)

        let result = NotificationGrouping.grouped(spaces: [live, ghost], services: [alpha, beta])

        // Only the live space is grouped; the ghost's dangling link is skipped
        // and Beta appears nowhere. Without the guard, Ghost/Beta would show.
        XCTAssertEqual(result.groups.map { $0.space?.name }, ["Live"])
        XCTAssertEqual(result.groups.first?.services.map(\.label), ["Alpha"])
        XCTAssertFalse(result.groups.contains { group in
            group.services.contains { $0.label == "Beta" }
        })
    }

    // MARK: - Move service to space

    func testEligibleSpaceIDsExcludesCurrentMemberships() {
        let a = UUID(), b = UUID(), c = UUID()
        // A service that lives in `a` can be moved to `b` and `c`, not `a`.
        XCTAssertEqual(
            SpaceMove.eligibleSpaceIDs(allSpaceIDs: [a, b, c], memberSpaceIDs: [a]),
            [b, c]
        )
        // Order follows `allSpaceIDs` (the sorted space rail).
        XCTAssertEqual(
            SpaceMove.eligibleSpaceIDs(allSpaceIDs: [c, a, b], memberSpaceIDs: [a]),
            [c, b]
        )
    }

    func testEligibleSpaceIDsEmptyWhenServiceIsEverywhere() {
        let a = UUID(), b = UUID()
        // Already a member of every space → nothing to move into (menu falls
        // back to "New Space…" only).
        XCTAssertEqual(
            SpaceMove.eligibleSpaceIDs(allSpaceIDs: [a, b], memberSpaceIDs: [a, b]),
            []
        )
        // No spaces at all → nothing eligible.
        XCTAssertEqual(
            SpaceMove.eligibleSpaceIDs(allSpaceIDs: [], memberSpaceIDs: [a]),
            []
        )
    }

    /// Exercises the SwiftData reassignment behind `ServiceSidebarView.moveService`
    /// against a real in-memory store: repointing a link's `space` relocates the
    /// service between spaces (the source space loses it, the target gains it at
    /// the tail) and never leaves the service with zero or duplicate links.
    @MainActor
    func testMoveServiceRelocatesLinkBetweenSpacesAtTail() throws {
        let container = try ModelContainer(
            for: Space.self, ServiceInstance.self, SpaceServiceLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext

        let spaceA = Space(name: "A", emoji: "🅰️", sortOrder: 0)
        let spaceB = Space(name: "B", emoji: "🅱️", sortOrder: 1)
        let moving = ServiceInstance(label: "Slack", url: "https://s.example")
        let residentOfB = ServiceInstance(label: "Gmail", url: "https://g.example")
        [spaceA, spaceB].forEach(ctx.insert)
        [moving, residentOfB].forEach(ctx.insert)

        let movingLink = SpaceServiceLink(sortOrder: 0, space: spaceA, service: moving)
        let bLink = SpaceServiceLink(sortOrder: 0, space: spaceB, service: residentOfB)
        [movingLink, bLink].forEach(ctx.insert)
        try ctx.save()

        // Replicate moveService: compute the target's tail order *before*
        // repointing, then reassign the link's space.
        let before = try ctx.fetch(FetchDescriptor<SpaceServiceLink>())
        let targetOrders = before.filter { $0.space.id == spaceB.id }.map(\.sortOrder)
        movingLink.sortOrder = (targetOrders.max() ?? -1) + 1
        movingLink.space = spaceB
        try ctx.save()

        let after = try ctx.fetch(FetchDescriptor<SpaceServiceLink>())
        let inA = after.filter { $0.space.id == spaceA.id }
        let inB = after.filter { $0.space.id == spaceB.id }.sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertTrue(inA.isEmpty, "source space should hold no links after the move")
        XCTAssertEqual(inB.map { $0.service.label }, ["Gmail", "Slack"], "moved service lands at the tail of the target")
        XCTAssertEqual(inB.last?.sortOrder, 1)
        // The service keeps exactly one link: no orphan, no double-link.
        XCTAssertEqual(after.filter { $0.service.id == moving.id }.count, 1)
    }

    // MARK: - Media permission resolution

    func testMediaEffectivePolicyPrefersServiceThenGlobalThenAsk() {
        // Explicit service value wins over the global default.
        XCTAssertEqual(MediaPermissionResolver.effectivePolicy(serviceRaw: "allow", globalRaw: "deny"), .allow)
        // Falls back to the global default when the service has no value.
        XCTAssertEqual(MediaPermissionResolver.effectivePolicy(serviceRaw: nil, globalRaw: "deny"), .deny)
        // Falls back to .ask when neither is set, or either is unparseable.
        XCTAssertEqual(MediaPermissionResolver.effectivePolicy(serviceRaw: nil, globalRaw: nil), .ask)
        XCTAssertEqual(MediaPermissionResolver.effectivePolicy(serviceRaw: "garbage", globalRaw: nil), .ask)
    }

    func testMediaResolveSingleTypeReadsTheMatchingField() {
        // .camera reads only the camera field.
        XCTAssertEqual(MediaPermissionResolver.resolve(.camera, camera: .allow, microphone: .deny), .grant)
        XCTAssertEqual(MediaPermissionResolver.resolve(.camera, camera: .deny, microphone: .allow), .deny)
        XCTAssertEqual(MediaPermissionResolver.resolve(.camera, camera: .ask, microphone: .allow), .ask)
        // .microphone reads only the microphone field.
        XCTAssertEqual(MediaPermissionResolver.resolve(.microphone, camera: .allow, microphone: .deny), .deny)
        XCTAssertEqual(MediaPermissionResolver.resolve(.microphone, camera: .deny, microphone: .allow), .grant)
        XCTAssertEqual(MediaPermissionResolver.resolve(.microphone, camera: .allow, microphone: .ask), .ask)
    }

    func testMediaResolveCameraAndMicrophoneIsMostRestrictive() {
        // Grant only when BOTH allow.
        XCTAssertEqual(MediaPermissionResolver.resolve(.cameraAndMicrophone, camera: .allow, microphone: .allow), .grant)
        // Deny if EITHER denies (deny beats ask and allow).
        XCTAssertEqual(MediaPermissionResolver.resolve(.cameraAndMicrophone, camera: .deny, microphone: .allow), .deny)
        XCTAssertEqual(MediaPermissionResolver.resolve(.cameraAndMicrophone, camera: .ask, microphone: .deny), .deny)
        // Ask if EITHER asks and neither denies.
        XCTAssertEqual(MediaPermissionResolver.resolve(.cameraAndMicrophone, camera: .ask, microphone: .allow), .ask)
        XCTAssertEqual(MediaPermissionResolver.resolve(.cameraAndMicrophone, camera: .allow, microphone: .ask), .ask)
    }

    func testMediaPolicyAccessorsDefaultToAskAndRoundTrip() {
        let service = ServiceInstance(label: "S", url: "https://s.example")
        // Unset → .ask, and the raw stays nil so resolution can fall back to global.
        XCTAssertEqual(service.cameraPolicy, .ask)
        XCTAssertEqual(service.microphonePolicy, .ask)
        XCTAssertNil(service.cameraPolicyRaw)
        XCTAssertNil(service.microphonePolicyRaw)
        // Setting pins the raw string.
        service.cameraPolicy = .allow
        service.microphonePolicy = .deny
        XCTAssertEqual(service.cameraPolicyRaw, "allow")
        XCTAssertEqual(service.microphonePolicyRaw, "deny")
        XCTAssertEqual(service.cameraPolicy, .allow)
        XCTAssertEqual(service.microphonePolicy, .deny)
    }

    func testMediaAskedFieldsGatesByRequestKind() {
        // A mic-only request with BOTH fields unset (.ask) marks ONLY the mic as
        // asked — so answering the prompt can never silently pin the camera to
        // Allow (the cross-device over-grant this guards).
        var asked = MediaPermissionResolver.askedFields(.microphone, camera: .ask, microphone: .ask)
        XCTAssertFalse(asked.camera)
        XCTAssertTrue(asked.microphone)
        // Camera-only request → only the camera.
        asked = MediaPermissionResolver.askedFields(.camera, camera: .ask, microphone: .ask)
        XCTAssertTrue(asked.camera)
        XCTAssertFalse(asked.microphone)
        // Combined request marks a field only when it's actually .ask; an
        // already-explicit field is left out so it isn't overwritten.
        asked = MediaPermissionResolver.askedFields(.cameraAndMicrophone, camera: .ask, microphone: .allow)
        XCTAssertTrue(asked.camera)
        XCTAssertFalse(asked.microphone)
        asked = MediaPermissionResolver.askedFields(.cameraAndMicrophone, camera: .ask, microphone: .ask)
        XCTAssertTrue(asked.camera)
        XCTAssertTrue(asked.microphone)
    }

    func testMediaPromptCopyNamesTheRealRequester() {
        // The service's own origin — the prompt names the service.
        let own = AppState.MediaPermissionRequest(
            id: UUID(), serviceLabel: "Slack", originHost: nil, camAsked: false, micAsked: true)
        XCTAssertEqual(own.title, "Allow Slack to use your microphone?")
        XCTAssertTrue(own.message.hasPrefix("Slack wants to use your microphone"))
        // A cross-domain origin — the prompt names the ORIGIN (not the service),
        // and the body says which service opened it, so it can't spoof the service.
        let foreign = AppState.MediaPermissionRequest(
            id: UUID(), serviceLabel: "Messenger", originHost: "messenger.com", camAsked: true, micAsked: true)
        XCTAssertEqual(foreign.title, "Allow messenger.com to use your camera and microphone?")
        XCTAssertTrue(foreign.message.hasPrefix("messenger.com, opened by Messenger"))
    }

    @MainActor
    func testForeignCaptureOutcomeGrantsSilentlyOnlyForFirstPartyAllow() {
        // A first-party vendor pinned to Allow, calling from a foreign MAIN-frame
        // origin (Messenger: facebook.com → messenger.com): silent grant, the
        // seamless-call case the flag exists for.
        XCTAssertEqual(
            AppState.foreignCaptureOutcome(
                isMainFrame: true, originHost: "messenger.com", isFirstParty: true, resolution: .grant),
            .grantSilently)

        // A first-party vendor still on Ask does NOT silently grant a foreign
        // origin — it prompts, and the prompt names the real origin.
        XCTAssertEqual(
            AppState.foreignCaptureOutcome(
                isMainFrame: true, originHost: "messenger.com", isFirstParty: true, resolution: .ask),
            .promptNamingOrigin)

        // A non-first-party service, even pinned Allow, never silently grants a
        // foreign origin (this was the shared-suffix leak) — it prompts.
        XCTAssertEqual(
            AppState.foreignCaptureOutcome(
                isMainFrame: true, originHost: "evil.example.com", isFirstParty: false, resolution: .grant),
            .promptNamingOrigin)

        // A third-party SUBFRAME fails closed even for a first-party Allow vendor.
        XCTAssertEqual(
            AppState.foreignCaptureOutcome(
                isMainFrame: false, originHost: "messenger.com", isFirstParty: true, resolution: .grant),
            .deny)

        // An empty origin fails closed.
        XCTAssertEqual(
            AppState.foreignCaptureOutcome(
                isMainFrame: true, originHost: "", isFirstParty: true, resolution: .grant),
            .deny)
    }

    func testCatalogFlagsFirstPartyCallVendors() {
        let entries = ServiceCatalog.shared.entries
        func firstParty(_ id: String) -> Bool? { entries.first { $0.id == id }?.firstParty }
        // The curated cross-domain / named call vendors are flagged.
        for id in ["messenger", "teams", "facebook", "whatsapp", "google-meet", "google-chat"] {
            XCTAssertEqual(firstParty(id), true, "\(id) should be flagged firstParty")
        }
        // Single-domain services are not (no benefit, keep the trust surface small).
        XCTAssertNotEqual(firstParty("discord"), true)
        XCTAssertNotEqual(firstParty("slack"), true)
    }

    @MainActor
    func testShouldBustCachesOnlyAfterAVersionChange() {
        // Fresh install (no previous version) — nothing stale to bust.
        XCTAssertFalse(AppState.shouldBustCachesOnLaunch(previousVersion: nil, currentVersion: "1.5.3"))
        // Normal relaunch on the same version — no bust.
        XCTAssertFalse(AppState.shouldBustCachesOnLaunch(previousVersion: "1.5.3", currentVersion: "1.5.3"))
        // Updated to a new version — bust the icon caches.
        XCTAssertTrue(AppState.shouldBustCachesOnLaunch(previousVersion: "1.5.2", currentVersion: "1.5.3"))
        // Unknown current version (missing Info key) — don't bust spuriously.
        XCTAssertFalse(AppState.shouldBustCachesOnLaunch(previousVersion: "1.5.2", currentVersion: ""))
    }
}
