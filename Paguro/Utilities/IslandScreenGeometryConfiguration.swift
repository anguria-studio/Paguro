import PaguroCore
import Foundation

/// Selects the public system provider or a Debug-only fixed screen preset.
enum IslandScreenGeometryConfiguration {
    static let launchArgument = "--paguro-island-screen"
    static let fakeNotchArgument = "--paguro-fake-notch"

    nonisolated static func simulatedPreset(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SimulatedScreenGeometryPreset? {
        #if DEBUG
        guard let value = launchValue(in: arguments) else { return nil }
        return SimulatedScreenGeometryPreset(rawValue: value)
        #else
        return nil
        #endif
    }

    nonisolated static func usesFakeNotch(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains(fakeNotchArgument)
        #else
        false
        #endif
    }

    @MainActor
    static func makeProvider(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        systemProvider: (any ScreenGeometryProvider)? = nil
    ) -> any ScreenGeometryProvider {
        if let preset = simulatedPreset(arguments: arguments) {
            return SimulatedScreenGeometryProvider(preset: preset)
        }
        let provider = systemProvider ?? SystemScreenGeometryProvider()
        if usesFakeNotch(arguments: arguments) {
            return FakeNotchScreenGeometryProvider(base: provider)
        }
        return provider
    }

    private nonisolated static func launchValue(in arguments: [String]) -> String? {
        let valuePrefix = "\(launchArgument)="
        if let combinedArgument = arguments.first(where: { $0.hasPrefix(valuePrefix) }) {
            return String(combinedArgument.dropFirst(valuePrefix.count))
        }

        guard let argumentIndex = arguments.firstIndex(of: launchArgument) else {
            return nil
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

/// Adds a Debug-only camera housing to the selected real display geometry.
private struct FakeNotchScreenGeometryProvider: ScreenGeometryProvider {
    let base: any ScreenGeometryProvider

    func currentSnapshot() async -> IslandScreenSnapshot {
        SimulatedCameraHousing.applying(to: await base.currentSnapshot())
    }
}
