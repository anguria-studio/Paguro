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

/// Rules for the rail that carries the services.
///
/// A layout gives the services one rail and, in the two-rail layouts, gives the
/// workspaces another. The service rail groups its own cells under workspace
/// names only while it is the single rail: with a workspace rail beside it,
/// every workspace is already on screen and the service rail carries the
/// current workspace alone.
public enum RailBarPresentationPolicy {
    /// The service rail groups its cells under workspace names.
    ///
    /// One workspace needs no name above its own services, so the rail keeps
    /// its plain form until a second workspace exists. A separate workspace
    /// rail replaces the grouping altogether.
    public static func groupsByWorkspace(
        mode: WorkspaceViewMode,
        workspaceCount: Int,
        hasWorkspaceRail: Bool
    ) -> Bool {
        !hasWorkspaceRail && mode == .all && workspaceCount > 1
    }

    /// The workspace-view setting is offered while one rail carries both
    /// workspaces and services. With a workspace rail on screen there is
    /// nothing left for it to choose.
    public static func offersWorkspaceView(hasWorkspaceRail: Bool) -> Bool {
        !hasWorkspaceRail
    }

    /// The icons-only option is offered while the services are in the bar. A
    /// rail row is a full-width row whose name costs no space, so a service
    /// rail on the left keeps its names.
    public static func offersIconsOnly(servicesInBar: Bool) -> Bool {
        servicesInBar
    }

    /// The bar drops its service names.
    public static func showsIconsOnly(servicesInBar: Bool, iconsOnlyPreference: Bool) -> Bool {
        iconsOnlyPreference && offersIconsOnly(servicesInBar: servicesInBar)
    }

    /// A workspace cell falls back to a default icon.
    ///
    /// Only the collapsed workspace rail needs one: it shows icons alone, and a
    /// workspace without an emoji would be an empty tile. Everywhere else a
    /// workspace with no emoji keeps showing its name and nothing else, which
    /// is a choice people make on purpose.
    public static func showsWorkspaceFallbackIcon(
        emoji: String,
        isIconOnlyWorkspaceRail: Bool
    ) -> Bool {
        isIconOnlyWorkspaceRail && WorkspaceEmoji.displayValue(emoji) == nil
    }
}
