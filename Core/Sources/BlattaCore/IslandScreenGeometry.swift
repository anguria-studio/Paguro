/// A point in the global macOS screen coordinate space.
public struct IslandScreenPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A size in logical screen points.
public struct IslandScreenSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

/// A rectangle in the global macOS screen coordinate space.
public struct IslandScreenRect: Equatable, Sendable {
    public let origin: IslandScreenPoint
    public let size: IslandScreenSize

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = IslandScreenPoint(x: x, y: y)
        self.size = IslandScreenSize(width: width, height: height)
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + (size.width / 2) }
    public var midY: Double { origin.y + (size.height / 2) }

    public func contains(_ point: IslandScreenPoint) -> Bool {
        point.x >= minX
            && point.x <= maxX
            && point.y >= minY
            && point.y <= maxY
    }
}

/// Insets from the full screen frame to its unobscured safe area.
public struct IslandScreenInsets: Equatable, Sendable {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(
        top: Double = 0,
        left: Double = 0,
        bottom: Double = 0,
        right: Double = 0
    ) {
        self.top = max(0, top)
        self.left = max(0, left)
        self.bottom = max(0, bottom)
        self.right = max(0, right)
    }
}

/// One display snapshot without an AppKit dependency.
public struct IslandScreenGeometry: Equatable, Sendable {
    public let identifier: String
    public let frame: IslandScreenRect
    public let visibleFrame: IslandScreenRect
    public let safeAreaInsets: IslandScreenInsets
    public let auxiliaryTopLeftArea: IslandScreenRect?
    public let auxiliaryTopRightArea: IslandScreenRect?
    public let backingScaleFactor: Double

    public init(
        identifier: String,
        frame: IslandScreenRect,
        visibleFrame: IslandScreenRect,
        safeAreaInsets: IslandScreenInsets = IslandScreenInsets(),
        auxiliaryTopLeftArea: IslandScreenRect? = nil,
        auxiliaryTopRightArea: IslandScreenRect? = nil,
        backingScaleFactor: Double = 1
    ) {
        self.identifier = identifier
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.backingScaleFactor = max(1, backingScaleFactor)
    }

    public var cameraHousingFrame: IslandScreenRect? {
        guard safeAreaInsets.top > 0,
              let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else {
            return nil
        }

        let width = rightArea.minX - leftArea.maxX
        let lowerEdge = max(leftArea.minY, rightArea.minY)
        let upperEdge = min(leftArea.maxY, rightArea.maxY)
        guard width > 0, upperEdge > lowerEdge else { return nil }

        return IslandScreenRect(
            x: leftArea.maxX,
            y: lowerEdge,
            width: width,
            height: upperEdge - lowerEdge
        )
    }

    public var hasCameraHousing: Bool {
        cameraHousingFrame != nil
    }
}

/// One point-in-time view of all available displays.
public struct IslandScreenSnapshot: Equatable, Sendable {
    public let screens: [IslandScreenGeometry]
    public let activeScreenIdentifier: String?
    public let primaryScreenIdentifier: String?

    public init(
        screens: [IslandScreenGeometry],
        activeScreenIdentifier: String?,
        primaryScreenIdentifier: String?
    ) {
        self.screens = screens
        self.activeScreenIdentifier = activeScreenIdentifier
        self.primaryScreenIdentifier = primaryScreenIdentifier
    }

    public var selectedScreen: IslandScreenGeometry? {
        screen(withIdentifier: activeScreenIdentifier)
            ?? screen(withIdentifier: primaryScreenIdentifier)
            ?? screens.first
    }

    private func screen(withIdentifier identifier: String?) -> IslandScreenGeometry? {
        guard let identifier else { return nil }
        return screens.first { $0.identifier == identifier }
    }
}

/// Supplies current screen values without exposing AppKit to feature code.
public protocol ScreenGeometryProvider: Sendable {
    func currentSnapshot() async -> IslandScreenSnapshot
}

/// The form that the island uses for one display.
public enum NotificationIslandPlacementStyle: Equatable, Sendable {
    case cameraHousing
}

/// A resolved island panel frame for one display.
public struct NotificationIslandPlacement: Equatable, Sendable {
    public let screenIdentifier: String
    public let style: NotificationIslandPlacementStyle
    public let frame: IslandScreenRect

    public init(
        screenIdentifier: String,
        style: NotificationIslandPlacementStyle,
        frame: IslandScreenRect
    ) {
        self.screenIdentifier = screenIdentifier
        self.style = style
        self.frame = frame
    }
}

/// Pure placement rules for a display with a camera housing.
public enum NotificationIslandGeometryPolicy {
    public static let defaultScreenMargin: Double = 8

    public static func placement(
        on screen: IslandScreenGeometry,
        desiredSize: IslandScreenSize,
        screenMargin: Double = defaultScreenMargin
    ) -> NotificationIslandPlacement? {
        guard desiredSize.width > 0, desiredSize.height > 0 else { return nil }

        guard let housingFrame = screen.cameraHousingFrame else { return nil }
        let frame = topAttachedFrame(
            around: housingFrame,
            in: screen.frame,
            desiredSize: desiredSize,
            horizontalMargin: max(0, screenMargin)
        )
        return NotificationIslandPlacement(
            screenIdentifier: screen.identifier,
            style: .cameraHousing,
            frame: frame
        )
    }

    private static func topAttachedFrame(
        around housingFrame: IslandScreenRect,
        in screenFrame: IslandScreenRect,
        desiredSize: IslandScreenSize,
        horizontalMargin: Double
    ) -> IslandScreenRect {
        let availableWidth = max(0, screenFrame.size.width - (horizontalMargin * 2))
        let width = min(desiredSize.width, availableWidth)
        let height = min(desiredSize.height, screenFrame.size.height)
        let proposedX = housingFrame.midX - (width / 2)
        let x = clampedOrigin(
            proposedX,
            minimum: screenFrame.minX + horizontalMargin,
            maximum: screenFrame.maxX - horizontalMargin - width
        )

        return IslandScreenRect(
            x: x,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    private static func clampedOrigin(
        _ value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        guard maximum >= minimum else { return minimum }
        return min(maximum, max(minimum, value))
    }
}
