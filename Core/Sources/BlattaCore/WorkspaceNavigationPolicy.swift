/// Controls how workspaces are presented in the service sidebar.
public enum WorkspaceViewMode: String, CaseIterable, Sendable {
    case current
    case all

    public static let defaultMode = Self.all

    public static func resolving(_ storedValue: String?) -> Self {
        storedValue.flatMap(Self.init(rawValue:)) ?? defaultMode
    }
}

/// Pure rules shared by the workspace sections and their service rows.
public enum WorkspaceNavigationPolicy {
    /// A total is useful only when the service rows that contribute to it are hidden.
    public static func showsAggregateBadge(serviceRowsVisible: Bool) -> Bool {
        !serviceRowsVisible
    }

    /// Drag reorder changes order only. Moving a service to another workspace
    /// remains an explicit context-menu action.
    public static func allowsReorder<WorkspaceID: Equatable>(
        sourceWorkspaceID: WorkspaceID,
        targetWorkspaceID: WorkspaceID
    ) -> Bool {
        sourceWorkspaceID == targetWorkspaceID
    }
}
