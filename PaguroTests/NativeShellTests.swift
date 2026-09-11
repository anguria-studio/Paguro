import XCTest
import AppKit
import Observation
import SwiftData
import SwiftUI
import PaguroCore
@testable import Paguro

final class NativeShellTests: XCTestCase {
    @MainActor
    func testLockScreenDoesNotAuthenticateOnAppearanceOrReappearance() async {
        var authenticationRequests = 0

        // Repeat presentation to cover reopening a locked window. The hosting
        // views stay offscreen throughout the test.
        for _ in 0..<2 {
            let appeared = expectation(description: "Lock screen appeared")
            let view = NSHostingView(rootView: LockView {
                authenticationRequests += 1
            }.onAppear { appeared.fulfill() })
            view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
            view.layoutSubtreeIfNeeded()
            await fulfillment(of: [appeared], timeout: 2)

            XCTAssertEqual(authenticationRequests, 0)
        }
    }

    private var dockSizing: DockSizing {
        DockSizing(
            baseSize: 22,
            magnifiedSize: 44,
            magnificationEnabled: true,
            isCollapsed: true,
            itemCount: 5,
            spaceAbove: .infinity
        )
    }

    @MainActor
    func testDockMagnificationSizesEveryIconFromThePointer() {
        let state = DockMagnificationState()
        let sizing = dockSizing

        // Nothing is magnified until the pointer is in the rail.
        XCTAssertEqual(state.iconTransform(atIndex: 2, sizing: sizing), DockIconTransform())

        state.movePointer(toRows: 2, reduceMotion: true)
        let hovered = state.iconTransform(atIndex: 2, sizing: sizing)
        let neighbor = state.iconTransform(atIndex: 1, sizing: sizing)
        let far = state.iconTransform(atIndex: 0, sizing: sizing)

        XCTAssertEqual(hovered.scale, 2, accuracy: 0.000_001)
        XCTAssertEqual(
            neighbor.scale,
            state.iconTransform(atIndex: 3, sizing: sizing).scale,
            accuracy: 0.000_001
        )
        XCTAssertGreaterThan(neighbor.scale, far.scale)
        XCTAssertGreaterThan(far.scale, 1)

        // The icon under the pointer keeps its place. The ones above it move
        // up, out of its way.
        XCTAssertEqual(hovered.verticalOffset, 0, accuracy: 0.000_001)
        XCTAssertLessThan(far.verticalOffset, neighbor.verticalOffset)
        XCTAssertLessThan(neighbor.verticalOffset, 0)
    }

    @MainActor
    func testDockMagnificationRestsAgainWhenThePointerLeaves() {
        let state = DockMagnificationState()
        let sizing = dockSizing

        state.movePointer(toRows: 1, reduceMotion: true)
        XCTAssertFalse(state.iconTransform(atIndex: 1, sizing: sizing).isResting)

        state.endPointerTracking(reduceMotion: true)
        XCTAssertEqual(state.iconTransform(atIndex: 1, sizing: sizing), DockIconTransform())
    }

    /// A pointer that comes back while the effect is fading raises it again.
    /// Asking only whether the rail has a position would leave the effect down
    /// with the pointer inside the rail.
    @MainActor
    func testDockMagnificationRisesAgainForAPointerThatReturns() {
        let state = DockMagnificationState()
        let sizing = dockSizing

        state.movePointer(toRows: 1, reduceMotion: true)
        state.endPointerTracking(reduceMotion: true)
        state.movePointer(toRows: 1, reduceMotion: true)

        XCTAssertEqual(state.iconTransform(atIndex: 1, sizing: sizing).scale, 2, accuracy: 0.000_001)
    }

    @MainActor
    func testDockMagnificationExpandedRailNeverMagnifies() {
        let state = DockMagnificationState()
        var sizing = dockSizing
        sizing.isCollapsed = false

        state.movePointer(toRows: 2, reduceMotion: true)

        XCTAssertEqual(state.iconTransform(atIndex: 2, sizing: sizing), DockIconTransform())
    }

    @MainActor
    func testDockMagnificationEntryCancelsAPendingExit() async {
        let first = UUID()
        let second = UUID()
        let state = DockMagnificationState()

        state.beginHover(for: first)
        state.endHover(for: first, after: .milliseconds(40))
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(state.hoveredLinkID, first)

        state.beginHover(for: second)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(state.hoveredLinkID, second)
        state.clearHover()
        XCTAssertNil(state.hoveredLinkID)
    }

    @MainActor
    func testDockTargetUsesThePointerPositionKeptByTheRail() {
        let state = DockMagnificationState()
        var sizing = dockSizing
        sizing.spaceAbove = 0
        let rowHeight = DockIconSizing.rowHeight(displayedIconSize: sizing.baseSize)
        let lastIndex = sizing.itemCount - 1
        let pointerPosition = (Double(sizing.itemCount) * rowHeight) + 5
        let pointerRows = DockIconSizing.pointerRows(
            pointerPosition: pointerPosition,
            topPadding: 0,
            baseSize: sizing.baseSize
        )

        state.movePointer(
            toRows: pointerRows,
            position: pointerPosition,
            reduceMotion: true
        )

        XCTAssertEqual(state.targetIndex(sizing: sizing), lastIndex)
    }

    /// The model raises the progress to 1 as the animation starts, while the
    /// drawing needs the complete duration. A click in that window must answer
    /// for the stack that a person sees.
    @MainActor
    func testDockTargetFollowsTheDrawnProgressWhileTheRailMagnifies() async {
        var sizing = dockSizing
        sizing.spaceAbove = 0
        let rowHeight = DockIconSizing.rowHeight(displayedIconSize: sizing.baseSize)
        let lastIndex = sizing.itemCount - 1
        // A point below the resting stack. It belongs to no item at rest, and
        // to the last item once the magnification pushes the stack down.
        let pointerPosition = (Double(sizing.itemCount) * rowHeight)
            + (rowHeight * 0.25)
        let pointerRows = DockIconSizing.pointerRows(
            pointerPosition: pointerPosition,
            topPadding: 0,
            baseSize: sizing.baseSize
        )

        let rising = DockMagnificationState(magnificationSeconds: 30)
        rising.movePointer(toRows: pointerRows, position: pointerPosition)
        XCTAssertEqual(rising.magnificationProgress, 1)
        XCTAssertNil(rising.targetIndex(sizing: sizing))
        rising.clearHover()

        let risen = DockMagnificationState(magnificationSeconds: 0.05)
        risen.movePointer(toRows: pointerRows, position: pointerPosition)
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(risen.targetIndex(sizing: sizing), lastIndex)
        risen.clearHover()
    }

    /// The pointer stays on one item for many events. Repeating the route must
    /// not write the identity that every cell reads, and it must keep the item.
    @MainActor
    func testRoutingToTheHoveredItemKeepsItAndCancelsAPendingExit() async {
        let linkID = UUID()
        let state = DockMagnificationState()

        state.movePointer(toRows: 1, position: 70, reduceMotion: true)
        state.routeHover(to: linkID, reduceMotion: true)
        state.endHover(for: linkID, after: .milliseconds(40), reduceMotion: true)

        // Observation reports a write, not a new value. A repeated route must
        // make no write at all, because every cell reads this property.
        let changed = ObservedChangeFlag()
        withObservationTracking {
            _ = state.hoveredLinkID
        } onChange: {
            changed.didChange = true
        }
        state.routeHover(to: linkID, reduceMotion: true)
        XCTAssertFalse(changed.didChange)

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(state.hoveredLinkID, linkID)
        state.clearHover()
    }

    @MainActor
    func testRailOwnsHoverIdentityWhileACellKeepsThePointerAlive() {
        let first = UUID()
        let overflowCell = UUID()
        let state = DockMagnificationState()

        state.movePointer(toRows: 1, position: 70, reduceMotion: true)
        state.routeHover(to: first, reduceMotion: true)
        state.setCellPointer(true, for: overflowCell, reduceMotion: true)
        state.endRailPointer(reduceMotion: true)

        XCTAssertEqual(state.hoveredLinkID, first)
        XCTAssertNotNil(state.pointerRows)
        XCTAssertEqual(state.magnificationProgress, 1)

        state.setCellPointer(false, for: overflowCell, reduceMotion: true)
        state.clearHover()
    }

    @MainActor
    func testHoverExitDoesNotDropAPointerThatRemainsInTheRail() async {
        let linkID = UUID()
        let state = DockMagnificationState()

        state.movePointer(toRows: 1, position: 70, reduceMotion: true)
        state.routeHover(to: linkID, reduceMotion: true)
        let hoverEnded = expectation(description: "The scheduled hover exit changes identity")
        withObservationTracking {
            _ = state.hoveredLinkID
        } onChange: {
            hoverEnded.fulfill()
        }
        state.endHover(for: linkID, after: .zero, reduceMotion: true)
        let result = await XCTWaiter.fulfillment(of: [hoverEnded], timeout: 2)
        XCTAssertEqual(result, .completed)

        XCTAssertNil(state.hoveredLinkID)
        XCTAssertNotNil(state.pointerRows)
        XCTAssertEqual(state.magnificationProgress, 1)
    }

    @MainActor
    func testCellHoverCannotOverrideANilTargetResolvedByTheRail() async {
        let linkID = UUID()
        let state = DockMagnificationState()

        state.movePointer(toRows: 1, position: 70, reduceMotion: true)
        state.routeHover(to: linkID, reduceMotion: true)
        let hoverEnded = expectation(description: "Cell hover permits the rail's pending exit")
        withObservationTracking {
            _ = state.hoveredLinkID
        } onChange: {
            hoverEnded.fulfill()
        }
        state.endHover(for: linkID, after: .zero, reduceMotion: true)
        state.setCellPointer(true, for: linkID, reduceMotion: true)
        // Await the observable exit, not an assumed main-actor scheduling delay.
        let result = await XCTWaiter.fulfillment(of: [hoverEnded], timeout: 2)
        XCTAssertEqual(result, .completed)

        XCTAssertNil(state.hoveredLinkID)
        XCTAssertNotNil(state.pointerRows)
        XCTAssertEqual(state.magnificationProgress, 1)

        state.setCellPointer(false, for: linkID, reduceMotion: true)
        state.clearHover()
    }

    // MARK: - Notice shape and selection against focus

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

    func testGlassStyleResolutionAndFrostRelationships() {
        XCTAssertEqual(ShellGlassStyle.resolving(ShellGlassStyle.clear.rawValue), .clear)
        XCTAssertEqual(ShellGlassStyle.resolving("unsupported"), GlassLabDefaults.style)
        XCTAssertEqual(ShellGlassStyle.resolving(nil), GlassLabDefaults.style)
        XCTAssertLessThan(ShellGlassStyle.clear.frostOpacity, ShellGlassStyle.regular.frostOpacity)
        XCTAssertEqual(ShellGlassStyle.off.frostOpacity, ShellGlassStyle.regular.frostOpacity)
    }

    func testSidebarPresentationMapsToSharedGeometry() {
        XCTAssertEqual(SidebarPresentation.expanded.width, PaguroMetric.Sidebar.expandedWidth)
        XCTAssertEqual(SidebarPresentation.expanded.serviceRowHeight, PaguroMetric.Sidebar.rowHeight)
        XCTAssertEqual(SidebarPresentation.expanded.surfaceTopInset, PaguroMetric.Sidebar.surfaceInset)
        XCTAssertEqual(SidebarPresentation.expanded.surfaceBottomInset, PaguroMetric.Sidebar.surfaceInset)
        XCTAssertEqual(SidebarPresentation.expanded.contentTopInset, PaguroMetric.Sidebar.topBarHeight)
        XCTAssertEqual(
            SidebarPresentation.expanded.toggleCenterX,
            PaguroMetric.Sidebar.expandedWidth
                - PaguroMetric.Sidebar.expandedToggleTrailingInset
                - (PaguroMetric.Toolbar.sidebarToggleSize / 2)
        )
        XCTAssertTrue(SidebarPresentation.expanded.showsLabels)

        XCTAssertEqual(SidebarPresentation.collapsed.width, PaguroMetric.Sidebar.collapsedWidth)
        XCTAssertEqual(SidebarPresentation.collapsed.serviceRowHeight, PaguroMetric.Sidebar.dockRowHeight)
        XCTAssertEqual(
            SidebarPresentation.collapsed.surfaceTopInset,
            PaguroMetric.Sidebar.collapsedSurfaceTopInset
        )
        XCTAssertEqual(SidebarPresentation.collapsed.surfaceBottomInset, PaguroMetric.Sidebar.surfaceInset)
        XCTAssertEqual(
            SidebarPresentation.collapsed.contentTopInset,
            PaguroMetric.Sidebar.collapsedContentTopInset
        )
        XCTAssertEqual(
            SidebarPresentation.collapsed.toggleCenterX,
            PaguroMetric.Sidebar.collapsedWidth
                + PaguroMetric.Toolbar.collapsedLeadingInset
                + (PaguroMetric.Toolbar.sidebarToggleSize / 2)
        )
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

    // MARK: - Service health accessibility integration

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

    // MARK: - Space header and palette

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
        XCTAssertEqual(SpaceHeader.label(spaceName: nil, badgeCount: 0, isMuted: false), "No workspace")
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

    // MARK: - Menu-bar window layout

    /// The menu-bar window has no height of its own. It asks its content for a
    /// height, and it offers none while it asks. This measures the service
    /// list under that same question.
    @MainActor
    private func menuBarServiceListHeight(rowCount: Int) -> CGFloat {
        let list = MenuBarServiceList {
            ForEach(0..<rowCount, id: \.self) { index in
                Text("Service \(index)")
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            }
        }
        let controller = NSHostingController(rootView: AnyView(list.frame(width: 340)))
        return controller.sizeThatFits(in: CGSize(width: 340, height: 0)).height
    }

    /// A scroll view accepts a height of zero. Before the fix the list
    /// answered zero here, the window closed around its header and its footer,
    /// and no service row reached the screen.
    @MainActor
    func testMenuBarServiceListKeepsItsRowsWhenTheWindowOffersNoHeight() {
        let height = menuBarServiceListHeight(rowCount: 9)

        XCTAssertGreaterThanOrEqual(height, 9 * 34)
        XCTAssertLessThanOrEqual(height, MenuBarServiceListMetrics.maximumHeight)
    }

    /// A short list must not pad the window to the maximum height.
    @MainActor
    func testMenuBarServiceListTakesOnlyTheHeightOfAShortList() {
        // Two rows of 34 points, one 14-point gap, and 10 points of padding
        // above and below.
        XCTAssertEqual(menuBarServiceListHeight(rowCount: 2), 102, accuracy: 1)
    }

    /// A long list stops at the maximum height and scrolls inside it.
    @MainActor
    func testMenuBarServiceListStopsAtItsMaximumHeight() {
        XCTAssertEqual(
            menuBarServiceListHeight(rowCount: 30),
            MenuBarServiceListMetrics.maximumHeight,
            accuracy: 1
        )
    }
}

/// Records one observation change from the tracking closure, which runs
/// outside the actor of the test.
private final class ObservedChangeFlag: @unchecked Sendable {
    var didChange = false
}
