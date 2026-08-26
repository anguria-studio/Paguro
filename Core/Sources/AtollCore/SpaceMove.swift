/// Pure rules for moving a service between workspaces.
public enum SpaceMove {
    /// Returns every workspace that does not already contain the service.
    /// Result order follows `allSpaceIDs`.
    public static func eligibleSpaceIDs<ID: Hashable>(
        allSpaceIDs: [ID],
        memberSpaceIDs: Set<ID>
    ) -> [ID] {
        allSpaceIDs.filter { !memberSpaceIDs.contains($0) }
    }
}
