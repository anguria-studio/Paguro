import SwiftUI
import PaguroCore

/// One confirmation for each place that can delete a space.
///
/// The message states how many services Paguro deletes with the space.
/// That deletion also removes sign-in data and is not reversible, so every
/// entry point must show the same honest text.
struct DeleteSpaceConfirmation: ViewModifier {
    @Environment(AppState.self) private var appState
    @Binding var space: Space?
    let onDelete: (Space) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(space?.name ?? "workspace")?",
            isPresented: Binding(
                get: { space != nil },
                set: { if !$0 { space = nil } }
            ),
            titleVisibility: .visible,
            presenting: space
        ) { target in
            Button("Delete", role: .destructive) {
                onDelete(target)
                space = nil
            }
        } message: { target in
            Text(message(for: target))
        }
    }

    private func message(for space: Space) -> String {
        return WorkspaceDeletionMessage.text(
            orphanedServiceCount: appState.orphanedServiceCount(byDeletingSpace: space.id)
        )
    }
}

extension View {
    /// Shows the shared delete-space confirmation while `space` is not `nil`.
    func deleteSpaceConfirmation(
        space: Binding<Space?>,
        onDelete: @escaping (Space) -> Void
    ) -> some View {
        modifier(DeleteSpaceConfirmation(space: space, onDelete: onDelete))
    }
}
