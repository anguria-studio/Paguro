import BlattaCore
import XCTest
@testable import Blatta

final class IslandScreenGeometryConfigurationTests: XCTestCase {
    func testReadsCombinedDebugPresetArgument() {
        let preset = IslandScreenGeometryConfiguration.simulatedPreset(
            arguments: ["Blatta", "--blatta-island-screen=notched-14-inch"]
        )

        XCTAssertEqual(preset, .notched14Inch)
    }

    func testReadsSeparateDebugPresetArgument() {
        let preset = IslandScreenGeometryConfiguration.simulatedPreset(
            arguments: ["Blatta", "--blatta-island-screen", "external-display"]
        )

        XCTAssertEqual(preset, .externalDisplay)
    }

    func testRejectsMissingAndUnknownPresetValues() {
        XCTAssertNil(
            IslandScreenGeometryConfiguration.simulatedPreset(
                arguments: ["Blatta", "--blatta-island-screen"]
            )
        )
        XCTAssertNil(
            IslandScreenGeometryConfiguration.simulatedPreset(
                arguments: ["Blatta", "--blatta-island-screen=unknown"]
            )
        )
    }

    func testReadsTheDebugFakeNotchArgument() {
        XCTAssertTrue(
            IslandScreenGeometryConfiguration.usesFakeNotch(
                arguments: ["Blatta", "--blatta-fake-notch"]
            )
        )
        XCTAssertFalse(
            IslandScreenGeometryConfiguration.usesFakeNotch(
                arguments: ["Blatta"]
            )
        )
    }

    @MainActor
    func testFactoryUsesTheSimulatedProviderForADebugPreset() async {
        let provider = IslandScreenGeometryConfiguration.makeProvider(
            arguments: ["Blatta", "--blatta-island-screen=notched-16-inch"]
        )

        let snapshot = await provider.currentSnapshot()

        XCTAssertEqual(snapshot.selectedScreen?.identifier, "notched-16-inch")
    }

    @MainActor
    func testFactoryUsesTheGivenSystemProviderWithoutAPreset() async {
        let expectedSnapshot = SimulatedScreenGeometryPreset.externalDisplay
            .scenario
            .snapshot
        let fallbackProvider = FixedScreenGeometryProvider(
            snapshot: expectedSnapshot
        )
        let provider = IslandScreenGeometryConfiguration.makeProvider(
            arguments: ["Blatta"],
            systemProvider: fallbackProvider
        )

        let snapshot = await provider.currentSnapshot()

        XCTAssertEqual(snapshot, expectedSnapshot)
    }

    @MainActor
    func testFactoryAddsAFakeNotchToTheSelectedRealGeometry() async {
        let baseSnapshot = SimulatedScreenGeometryPreset.externalDisplay
            .scenario
            .snapshot
        let provider = IslandScreenGeometryConfiguration.makeProvider(
            arguments: ["Blatta", "--blatta-fake-notch"],
            systemProvider: FixedScreenGeometryProvider(snapshot: baseSnapshot)
        )

        let snapshot = await provider.currentSnapshot()

        XCTAssertTrue(snapshot.selectedScreen?.hasCameraHousing == true)
        XCTAssertEqual(snapshot.selectedScreen?.frame, baseSnapshot.selectedScreen?.frame)
    }
}

private struct FixedScreenGeometryProvider: ScreenGeometryProvider {
    let snapshot: IslandScreenSnapshot

    func currentSnapshot() async -> IslandScreenSnapshot {
        snapshot
    }
}
