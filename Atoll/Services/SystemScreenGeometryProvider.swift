import AppKit
import AtollCore

/// Reads public AppKit screen values when the island needs a fresh snapshot.
@MainActor
final class SystemScreenGeometryProvider: ScreenGeometryProvider {
    typealias ScreensResolver = @MainActor @Sendable () -> [NSScreen]
    typealias ActiveScreenResolver = @MainActor @Sendable () -> NSScreen?

    private let screensResolver: ScreensResolver
    private let activeScreenResolver: ActiveScreenResolver

    init(
        screensResolver: @escaping ScreensResolver = { NSScreen.screens },
        activeScreenResolver: @escaping ActiveScreenResolver = {
            NSApp.windows.first(where: { window in
                window.isVisible && (
                    window.identifier?.rawValue == "main"
                        || (window.canBecomeMain
                            && window.styleMask.contains(.titled)
                            && window.title == "Atoll")
                )
            })?.screen
        }
    ) {
        self.screensResolver = screensResolver
        self.activeScreenResolver = activeScreenResolver
    }

    func currentSnapshot() async -> IslandScreenSnapshot {
        let screens = screensResolver()
        let entries = screens.enumerated().map { index, screen in
            ScreenEntry(
                screen: screen,
                geometry: geometry(for: screen, fallbackIndex: index)
            )
        }
        let activeScreen = activeScreenResolver()
        let activeIdentifier = entries.first { entry in
            entry.screen === activeScreen
        }?.geometry.identifier
        let primaryIdentifier = entries.first { entry in
            entry.screen.frame.origin == .zero
        }?.geometry.identifier ?? entries.first?.geometry.identifier

        return IslandScreenSnapshot(
            screens: entries.map(\.geometry),
            activeScreenIdentifier: activeIdentifier,
            primaryScreenIdentifier: primaryIdentifier
        )
    }

    private func geometry(
        for screen: NSScreen,
        fallbackIndex: Int
    ) -> IslandScreenGeometry {
        IslandScreenGeometry(
            identifier: identifier(for: screen, fallbackIndex: fallbackIndex),
            frame: screen.frame.islandScreenRect,
            visibleFrame: screen.visibleFrame.islandScreenRect,
            safeAreaInsets: IslandScreenInsets(
                top: screen.safeAreaInsets.top,
                left: screen.safeAreaInsets.left,
                bottom: screen.safeAreaInsets.bottom,
                right: screen.safeAreaInsets.right
            ),
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea?.islandScreenRect,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea?.islandScreenRect,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    private func identifier(for screen: NSScreen, fallbackIndex: Int) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[screenNumberKey] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "display-fallback-\(fallbackIndex)"
    }

    private struct ScreenEntry {
        let screen: NSScreen
        let geometry: IslandScreenGeometry
    }
}

private extension CGRect {
    var islandScreenRect: IslandScreenRect {
        IslandScreenRect(
            x: origin.x,
            y: origin.y,
            width: size.width,
            height: size.height
        )
    }
}
