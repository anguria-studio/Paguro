import BlattaCore
import Testing

struct SimulatedCameraHousingTests {
    @Test
    func addsHousingToTheSelectedDisplayAtItsRealTopEdge() throws {
        let original = SimulatedScreenGeometryPreset.externalDisplay
            .scenario
            .snapshot
        let transformed = SimulatedCameraHousing.applying(to: original)
        let screen = try #require(transformed.selectedScreen)

        #expect(screen.frame == original.selectedScreen?.frame)
        #expect(screen.cameraHousingFrame?.size.width == 164)
        #expect(screen.cameraHousingFrame?.size.height == 38)
        #expect(screen.cameraHousingFrame?.maxY == screen.frame.maxY)
    }

    @Test
    func changesOnlyTheSelectedDisplay() throws {
        let original = SimulatedScreenGeometryPreset.twoDisplayArrangement
            .scenario
            .snapshot
        let transformed = SimulatedCameraHousing.applying(to: original)
        let selectedIdentifier = try #require(original.selectedScreen?.identifier)

        for screen in transformed.screens {
            if screen.identifier == selectedIdentifier {
                #expect(screen.hasCameraHousing)
            } else {
                let originalScreen = original.screens.first {
                    $0.identifier == screen.identifier
                }
                #expect(screen == originalScreen)
            }
        }
    }

    @Test
    func invalidHousingSizeKeepsTheOriginalGeometry() throws {
        let original = try #require(
            SimulatedScreenGeometryPreset.externalDisplay.scenario.snapshot
                .selectedScreen
        )

        #expect(
            SimulatedCameraHousing.applying(
                to: original,
                width: 0,
                height: 38
            ) == original
        )
    }
}
