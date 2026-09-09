import SwiftUI
import PaguroCore

/// The context menu of one workspace, wherever a workspace is drawn.
///
/// The rail header, the grouped top bar, and the workspace rail all raise the
/// same menu. It lives in its own view rather than in one rail's extension, so
/// a second rail cannot drift a word or an action away from the first.
///
/// Editing and deleting are reported upward: both raise a sheet, and the owner
/// of the rail owns its sheets.
struct WorkspaceContextMenuItems: View {
    let space: Space
    /// Delete is left out for the last workspace: the app has no valid state
    /// with none, and `AppState.deleteSpace` refuses as well.
    let allowsDelete: Bool
    let onAddService: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        Toggle("Mute Workspace", isOn: Binding(
            get: { space.isMutedEffective },
            set: { appState.setWorkspaceMuted($0, for: space.id) }
        ))

        Divider()

        Button("Add Service…", action: onAddService)

        Button("Edit Workspace…", action: onEdit)

        if allowsDelete {
            Divider()
            Button("Delete Workspace", role: .destructive, action: onDelete)
        }
    }
}
