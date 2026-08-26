/// The side of a target where a moved item must be inserted.
public enum ServiceReorderPlacement: Sendable {
    case before
    case after
}

/// Pure rules for reordering service or workspace IDs.
public enum ServiceReorder {
    /// Returns the reordered IDs, or nil when the move is invalid or has no
    /// effect.
    public static func reorderedIDs<ID: Equatable>(
        _ ids: [ID],
        moving droppedID: ID,
        relativeTo targetID: ID,
        placement: ServiceReorderPlacement
    ) -> [ID]? {
        guard droppedID != targetID,
              let fromIndex = ids.firstIndex(of: droppedID),
              let targetIndex = ids.firstIndex(of: targetID) else {
            return nil
        }

        var reordered = ids
        let moved = reordered.remove(at: fromIndex)

        var toIndex = targetIndex
        if placement == .after {
            toIndex += 1
        }
        if fromIndex < toIndex {
            toIndex -= 1
        }
        guard fromIndex != toIndex else { return nil }

        reordered.insert(moved, at: toIndex)
        return reordered
    }
}
