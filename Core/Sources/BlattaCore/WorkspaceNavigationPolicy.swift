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

/// Rules for the rail that groups its services by workspace.
///
/// Both rail axes can show every workspace. The vertical rail draws one
/// disclosure section for each workspace; the top bar draws a workspace name
/// followed by that workspace's tabs. Icons-only drops the service names alone,
/// and it belongs to the top bar, so a stored `true` must never reach the
/// vertical rail.
public enum RailBarPresentationPolicy {
    /// The rail groups its services under workspace names.
    ///
    /// One workspace needs no name above its own services, so the rail keeps
    /// its plain form until a second workspace exists.
    public static func groupsByWorkspace(
        mode: WorkspaceViewMode,
        workspaceCount: Int
    ) -> Bool {
        mode == .all && workspaceCount > 1
    }

    /// The icons-only option is offered for the top bar alone. A sidebar row is
    /// a full-width row whose name costs no space, so it keeps its name in both
    /// workspace views.
    public static func offersIconsOnly(isTopBar: Bool) -> Bool {
        isTopBar
    }

    /// The rail drops its service names and workspace names.
    public static func showsIconsOnly(isTopBar: Bool, iconsOnlyPreference: Bool) -> Bool {
        iconsOnlyPreference && offersIconsOnly(isTopBar: isTopBar)
    }
}
