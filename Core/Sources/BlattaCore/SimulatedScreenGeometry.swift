/// Simulated menu-bar pressure for debug geometry checks.
public enum SimulatedMenuBarCrowding: Equatable, Sendable {
    case none
    case leading
    case trailing
}

/// A stable debug geometry scenario.
public struct SimulatedScreenGeometryScenario: Equatable, Sendable {
    public let snapshot: IslandScreenSnapshot
    public let menuBarCrowding: SimulatedMenuBarCrowding

    public init(
        snapshot: IslandScreenSnapshot,
        menuBarCrowding: SimulatedMenuBarCrowding = .none
    ) {
        self.snapshot = snapshot
        self.menuBarCrowding = menuBarCrowding
    }
}

/// Debug screen values that do not depend on the current Mac hardware.
public enum SimulatedScreenGeometryPreset: String, CaseIterable, Sendable {
    case notched14Inch = "notched-14-inch"
    case notched16Inch = "notched-16-inch"
    case nonNotchedLaptop = "non-notched-laptop"
    case externalDisplay = "external-display"
    case twoDisplayArrangement = "two-display-arrangement"
    case crowdedLeadingMenuBar = "crowded-leading-menu-bar"
    case crowdedTrailingMenuBar = "crowded-trailing-menu-bar"

    public var scenario: SimulatedScreenGeometryScenario {
        switch self {
        case .notched14Inch:
            return singleScreenScenario(screen: Self.notched14InchScreen)
        case .notched16Inch:
            return singleScreenScenario(screen: Self.notched16InchScreen)
        case .nonNotchedLaptop:
            return singleScreenScenario(screen: Self.nonNotchedLaptopScreen)
        case .externalDisplay:
            return singleScreenScenario(screen: Self.externalDisplayScreen)
        case .twoDisplayArrangement:
            return twoDisplayScenario
        case .crowdedLeadingMenuBar:
            return singleScreenScenario(
                screen: Self.notched14InchScreen,
                menuBarCrowding: .leading
            )
        case .crowdedTrailingMenuBar:
            return singleScreenScenario(
                screen: Self.notched14InchScreen,
                menuBarCrowding: .trailing
            )
        }
    }

    private func singleScreenScenario(
        screen: IslandScreenGeometry,
        menuBarCrowding: SimulatedMenuBarCrowding = .none
    ) -> SimulatedScreenGeometryScenario {
        SimulatedScreenGeometryScenario(
            snapshot: IslandScreenSnapshot(
                screens: [screen],
                activeScreenIdentifier: screen.identifier,
                primaryScreenIdentifier: screen.identifier
            ),
            menuBarCrowding: menuBarCrowding
        )
    }

    private var twoDisplayScenario: SimulatedScreenGeometryScenario {
        let laptop = Self.notched16InchScreen
        let external = Self.externalDisplayScreenAtRight
        return SimulatedScreenGeometryScenario(
            snapshot: IslandScreenSnapshot(
                screens: [laptop, external],
                activeScreenIdentifier: external.identifier,
                primaryScreenIdentifier: laptop.identifier
            )
        )
    }

    private static let notched14InchScreen = IslandScreenGeometry(
        identifier: "notched-14-inch",
        frame: IslandScreenRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: IslandScreenRect(x: 0, y: 72, width: 1_512, height: 872),
        safeAreaInsets: IslandScreenInsets(top: 38),
        auxiliaryTopLeftArea: IslandScreenRect(
            x: 0,
            y: 944,
            width: 674,
            height: 38
        ),
        auxiliaryTopRightArea: IslandScreenRect(
            x: 838,
            y: 944,
            width: 674,
            height: 38
        ),
        backingScaleFactor: 2
    )

    private static let notched16InchScreen = IslandScreenGeometry(
        identifier: "notched-16-inch",
        frame: IslandScreenRect(x: 0, y: 0, width: 1_728, height: 1_117),
        visibleFrame: IslandScreenRect(x: 0, y: 74, width: 1_728, height: 1_005),
        safeAreaInsets: IslandScreenInsets(top: 38),
        auxiliaryTopLeftArea: IslandScreenRect(
            x: 0,
            y: 1_079,
            width: 782,
            height: 38
        ),
        auxiliaryTopRightArea: IslandScreenRect(
            x: 946,
            y: 1_079,
            width: 782,
            height: 38
        ),
        backingScaleFactor: 2
    )

    private static let nonNotchedLaptopScreen = IslandScreenGeometry(
        identifier: "non-notched-laptop",
        frame: IslandScreenRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: IslandScreenRect(x: 0, y: 60, width: 1_440, height: 816),
        backingScaleFactor: 2
    )

    private static let externalDisplayScreen = IslandScreenGeometry(
        identifier: "external-display",
        frame: IslandScreenRect(x: 0, y: 0, width: 2_560, height: 1_440),
        visibleFrame: IslandScreenRect(x: 0, y: 80, width: 2_560, height: 1_335),
        backingScaleFactor: 2
    )

    private static let externalDisplayScreenAtRight = IslandScreenGeometry(
        identifier: "external-display-right",
        frame: IslandScreenRect(x: 1_728, y: 0, width: 2_560, height: 1_440),
        visibleFrame: IslandScreenRect(
            x: 1_728,
            y: 80,
            width: 2_560,
            height: 1_335
        ),
        backingScaleFactor: 2
    )
}

/// Supplies one fixed geometry scenario for tests and debug builds.
public struct SimulatedScreenGeometryProvider: ScreenGeometryProvider {
    public let scenario: SimulatedScreenGeometryScenario

    public init(preset: SimulatedScreenGeometryPreset) {
        self.scenario = preset.scenario
    }

    public init(scenario: SimulatedScreenGeometryScenario) {
        self.scenario = scenario
    }

    public func currentSnapshot() async -> IslandScreenSnapshot {
        scenario.snapshot
    }
}
