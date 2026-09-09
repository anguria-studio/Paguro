import Foundation
import PaguroCore

/// Keeps what each workspace was last left on, across launches.
///
/// It holds one service for each workspace, outside the model store: it is a
/// window state like the sidebar's own, not something a workspace owns. The
/// rules for reading it live in `WorkspaceServiceMemory`; this reads and writes
/// them.
@MainActor
struct WorkspaceSelectionStore {
    private(set) var memory: WorkspaceServiceMemory
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.memory = WorkspaceServiceMemory(
            lastServiceByWorkspace: Self.load(from: defaults)
        )
    }

    mutating func remember(serviceID: UUID, in workspaceID: UUID) {
        guard memory.lastService(in: workspaceID) != serviceID else { return }
        memory.remember(serviceID: serviceID, in: workspaceID)
        save()
    }

    mutating func forget(workspaceID: UUID) {
        guard memory.lastService(in: workspaceID) != nil else { return }
        memory.forget(workspaceID: workspaceID)
        save()
    }

    func serviceToOpen(
        in workspaceID: UUID,
        memberServiceIDs: [UUID],
        currentServiceID: UUID?
    ) -> UUID? {
        memory.serviceToOpen(
            in: workspaceID,
            memberServiceIDs: memberServiceIDs,
            currentServiceID: currentServiceID
        )
    }

    /// Stored as text pairs, which `UserDefaults` can hold as it is. A pair
    /// that no longer parses is dropped rather than kept as a broken entry.
    private static func load(from defaults: UserDefaults) -> [UUID: UUID] {
        let stored = defaults.dictionary(forKey: DefaultsKey.workspaceServiceMemory)
            as? [String: String] ?? [:]
        return stored.reduce(into: [:]) { result, pair in
            guard let workspaceID = UUID(uuidString: pair.key),
                  let serviceID = UUID(uuidString: pair.value)
            else { return }
            result[workspaceID] = serviceID
        }
    }

    private func save() {
        let stored = memory.stored.reduce(into: [String: String]()) { result, pair in
            result[pair.key.uuidString] = pair.value.uuidString
        }
        defaults.set(stored, forKey: DefaultsKey.workspaceServiceMemory)
    }
}
