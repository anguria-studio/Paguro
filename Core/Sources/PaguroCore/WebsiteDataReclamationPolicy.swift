import Foundation

/// Pure rules that protect live website data stores from reclamation.
public enum WebsiteDataReclamationPolicy {
    /// Separates valid tombstones from identifiers that a live service claims.
    public static func reconcile(
        tombstoned: Set<UUID>,
        claimed: Set<UUID>
    ) -> (keep: Set<UUID>, dropped: Set<UUID>) {
        let dropped = tombstoned.intersection(claimed)
        return (tombstoned.subtracting(dropped), dropped)
    }

    /// Returns unclaimed stores. An empty claim set is unknown and fails closed.
    public static func unreferenced(
        onDisk: Set<UUID>,
        claimed: Set<UUID>
    ) -> Set<UUID> {
        guard !claimed.isEmpty else { return [] }
        return onDisk.subtracting(claimed)
    }
}
