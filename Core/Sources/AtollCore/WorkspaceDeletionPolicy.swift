/// Pure membership rules for deleting a workspace.
public enum WorkspaceDeletionPolicy {
    /// Returns services that belong only to the workspace being deleted.
    public static func servicesOrphaned<ID: Hashable>(
        byDeletingSpace spaceID: ID,
        memberships: [ID: Set<ID>]
    ) -> Set<ID> {
        var orphaned: Set<ID> = []
        for (serviceID, spaces) in memberships
        where spaces.contains(spaceID) && spaces.subtracting([spaceID]).isEmpty {
            orphaned.insert(serviceID)
        }
        return orphaned
    }
}
