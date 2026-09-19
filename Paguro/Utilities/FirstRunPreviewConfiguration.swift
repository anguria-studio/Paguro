#if DEBUG
import Foundation
import SwiftData
import WebKit

/// Each preview launch starts with an empty, disposable account graph.
/// The normal app store and its recovery history must never enter this flow.
enum FirstRunPreviewConfiguration {
    static let launchArgument = "--paguro-first-run-preview"

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    @MainActor
    static func makeStore(schema: Schema) throws -> StoreLoader.PreparedStore {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let suite = "studio.anguria.paguro.first-run-preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return StoreLoader.PreparedStore(
            container: container,
            outcome: .openedClean,
            // No file is created here. Recovery sees no normal-store backups.
            url: FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString).appending(path: "default.store"),
            wasDamaged: false,
            defaults: defaults,
            allowsPersistentReclamation: false
        )
    }
}
#endif
