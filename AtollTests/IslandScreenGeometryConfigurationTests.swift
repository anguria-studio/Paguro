import AtollCore
import XCTest
@testable import Atoll

final class IslandScreenGeometryConfigurationTests: XCTestCase {
    func testReadsCombinedDebugPresetArgument() {
        let preset = IslandScreenGeometryConfiguration.simulatedPreset(
            arguments: ["Atoll", "--atoll-island-screen=notched-14-inch"]
        )

        XCTAssertEqual(preset, .notched14Inch)
    }

    func testReadsSeparateDebugPresetArgument() {
        let preset = IslandScreenGeometryConfiguration.simulatedPreset(
            arguments: ["Atoll", "--atoll-island-screen", "external-display"]
        )

        XCTAssertEqual(preset, .externalDisplay)
    }

    func testRejectsMissingAndUnknownPresetValues() {
        XCTAssertNil(
            IslandScreenGeometryConfiguration.simulatedPreset(
                arguments: ["Atoll", "--atoll-island-screen"]
            )
        )
        XCTAssertNil(
            IslandScreenGeometryConfiguration.simulatedPreset(
                arguments: ["Atoll", "--atoll-island-screen=unknown"]
            )
        )
    }

    @MainActor
    func testFactoryUsesTheSimulatedProviderForADebugPreset() async {
        let provider = IslandScreenGeometryConfiguration.makeProvider(
            arguments: ["Atoll", "--atoll-island-screen=notched-16-inch"]
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
            arguments: ["Atoll"],
            systemProvider: fallbackProvider
        )

        let snapshot = await provider.currentSnapshot()

        XCTAssertEqual(snapshot, expectedSnapshot)
    }
}

private struct FixedScreenGeometryProvider: ScreenGeometryProvider {
    let snapshot: IslandScreenSnapshot

    func currentSnapshot() async -> IslandScreenSnapshot {
        snapshot
    }
}
