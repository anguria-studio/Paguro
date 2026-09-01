import Testing
@testable import BlattaCore

struct IslandScreenGeometryTests {
    @Test
    func notchedPresetDerivesTheCameraHousing() {
        let screen = selectedScreen(for: .notched14Inch)

        #expect(screen.hasCameraHousing)
        #expect(
            screen.cameraHousingFrame
                == IslandScreenRect(x: 674, y: 944, width: 164, height: 38)
        )
    }

    @Test
    func standardDisplaysHaveNoCameraHousing() {
        let laptop = selectedScreen(for: .nonNotchedLaptop)
        let external = selectedScreen(for: .externalDisplay)

        #expect(!laptop.hasCameraHousing)
        #expect(!external.hasCameraHousing)
    }

    @Test
    func cameraPlacementIsCenteredAndTopAttached() throws {
        let screen = selectedScreen(for: .notched16Inch)
        let placement = try #require(
            NotificationIslandGeometryPolicy.placement(
                on: screen,
                desiredSize: IslandScreenSize(width: 360, height: 120)
            )
        )

        #expect(placement.style == .cameraHousing)
        #expect(placement.frame.midX == screen.cameraHousingFrame?.midX)
        #expect(placement.frame.maxY == screen.frame.maxY)
    }

    @Test
    func standardDisplayHasNoIslandPlacement() {
        let screen = selectedScreen(for: .externalDisplay)

        #expect(
            NotificationIslandGeometryPolicy.placement(
                on: screen,
                desiredSize: IslandScreenSize(width: 360, height: 120)
            ) == nil
        )
    }

    @Test
    func oversizedPlacementStaysInsideItsScreenBounds() throws {
        let screen = selectedScreen(for: .notched14Inch)
        let placement = try #require(
            NotificationIslandGeometryPolicy.placement(
                on: screen,
                desiredSize: IslandScreenSize(width: 9_000, height: 9_000)
            )
        )

        #expect(placement.frame.minX == screen.frame.minX + 8)
        #expect(placement.frame.maxX == screen.frame.maxX - 8)
        #expect(placement.frame.minY == screen.frame.minY)
        #expect(placement.frame.maxY == screen.frame.maxY)
    }

    @Test
    func invalidPanelSizeHasNoPlacement() {
        let screen = selectedScreen(for: .notched14Inch)

        #expect(
            NotificationIslandGeometryPolicy.placement(
                on: screen,
                desiredSize: IslandScreenSize(width: 0, height: 120)
            ) == nil
        )
    }

    @Test
    func activeDisplayTakesPriorityOverThePrimaryDisplay() {
        let snapshot = SimulatedScreenGeometryPreset.twoDisplayArrangement
            .scenario
            .snapshot

        #expect(snapshot.screens.count == 2)
        #expect(snapshot.selectedScreen?.identifier == "external-display-right")
    }

    @Test
    func selectionFallsBackToThePrimaryThenFirstDisplay() {
        let first = selectedScreen(for: .notched14Inch)
        let second = selectedScreen(for: .externalDisplay)
        let primaryFallback = IslandScreenSnapshot(
            screens: [first, second],
            activeScreenIdentifier: "missing",
            primaryScreenIdentifier: second.identifier
        )
        let firstFallback = IslandScreenSnapshot(
            screens: [first, second],
            activeScreenIdentifier: nil,
            primaryScreenIdentifier: nil
        )

        #expect(primaryFallback.selectedScreen == second)
        #expect(firstFallback.selectedScreen == first)
    }

    @Test
    func everyPresetHasAUsableSelectedScreen() {
        for preset in SimulatedScreenGeometryPreset.allCases {
            let screen = preset.scenario.snapshot.selectedScreen

            #expect(screen != nil, "Missing screen for \(preset.rawValue)")
            #expect(screen?.frame.size.width ?? 0 > 0)
            #expect(screen?.frame.size.height ?? 0 > 0)
            #expect(screen?.backingScaleFactor ?? 0 >= 1)
        }
    }

    @Test
    func crowdingPresetsDescribeOppositeMenuBarSides() {
        #expect(
            SimulatedScreenGeometryPreset.crowdedLeadingMenuBar
                .scenario
                .menuBarCrowding == .leading
        )
        #expect(
            SimulatedScreenGeometryPreset.crowdedTrailingMenuBar
                .scenario
                .menuBarCrowding == .trailing
        )
    }

    @Test
    func snapshotReportsACameraHousingOnAnyScreen() {
        #expect(SimulatedScreenGeometryPreset.notched14Inch
            .scenario.snapshot.hasCameraHousingScreen)
        // The external display is the selected screen of this arrangement, and
        // the notched laptop still makes the island available.
        #expect(SimulatedScreenGeometryPreset.twoDisplayArrangement
            .scenario.snapshot.hasCameraHousingScreen)
        #expect(!SimulatedScreenGeometryPreset.nonNotchedLaptop
            .scenario.snapshot.hasCameraHousingScreen)
        #expect(!SimulatedScreenGeometryPreset.externalDisplay
            .scenario.snapshot.hasCameraHousingScreen)
    }

    @Test
    func simulatedProviderReturnsItsFixedSnapshot() async {
        let provider = SimulatedScreenGeometryProvider(preset: .notched14Inch)

        let snapshot = await provider.currentSnapshot()

        #expect(snapshot == provider.scenario.snapshot)
    }

    private func selectedScreen(
        for preset: SimulatedScreenGeometryPreset
    ) -> IslandScreenGeometry {
        guard let screen = preset.scenario.snapshot.selectedScreen else {
            Issue.record("The preset has no selected screen: \(preset.rawValue)")
            return IslandScreenGeometry(
                identifier: "invalid",
                frame: IslandScreenRect(x: 0, y: 0, width: 0, height: 0),
                visibleFrame: IslandScreenRect(x: 0, y: 0, width: 0, height: 0)
            )
        }
        return screen
    }
}
