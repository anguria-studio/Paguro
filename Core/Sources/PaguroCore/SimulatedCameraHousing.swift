/// Adds a test camera housing to the selected display without changing its frame.
public enum SimulatedCameraHousing {
    public static let defaultWidth: Double = 164
    public static let defaultHeight: Double = 38

    public static func applying(
        to snapshot: IslandScreenSnapshot,
        width: Double = defaultWidth,
        height: Double = defaultHeight
    ) -> IslandScreenSnapshot {
        guard let selectedScreen = snapshot.selectedScreen else { return snapshot }
        let simulatedScreen = applying(
            to: selectedScreen,
            width: width,
            height: height
        )
        let screens = snapshot.screens.map { screen in
            screen.identifier == selectedScreen.identifier ? simulatedScreen : screen
        }
        return IslandScreenSnapshot(
            screens: screens,
            activeScreenIdentifier: snapshot.activeScreenIdentifier,
            primaryScreenIdentifier: snapshot.primaryScreenIdentifier
        )
    }

    public static func applying(
        to screen: IslandScreenGeometry,
        width: Double = defaultWidth,
        height: Double = defaultHeight
    ) -> IslandScreenGeometry {
        let housingHeight = min(max(0, height), screen.frame.size.height)
        let housingWidth = min(max(0, width), screen.frame.size.width)
        guard housingWidth > 0, housingHeight > 0 else { return screen }

        let sideWidth = (screen.frame.size.width - housingWidth) / 2
        let housingMinX = screen.frame.minX + sideWidth
        let topBandMinY = screen.frame.maxY - housingHeight

        return IslandScreenGeometry(
            identifier: screen.identifier,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: IslandScreenInsets(
                top: max(screen.safeAreaInsets.top, housingHeight),
                left: screen.safeAreaInsets.left,
                bottom: screen.safeAreaInsets.bottom,
                right: screen.safeAreaInsets.right
            ),
            auxiliaryTopLeftArea: IslandScreenRect(
                x: screen.frame.minX,
                y: topBandMinY,
                width: sideWidth,
                height: housingHeight
            ),
            auxiliaryTopRightArea: IslandScreenRect(
                x: housingMinX + housingWidth,
                y: topBandMinY,
                width: sideWidth,
                height: housingHeight
            ),
            backingScaleFactor: screen.backingScaleFactor
        )
    }
}
