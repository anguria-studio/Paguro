import SwiftUI

/// Keeps the service selected by the menu alive until confirmation finishes.
struct DeleteServiceConfirmation: ViewModifier {
    @Binding var link: LiveSpaceServiceLink?
    let onDelete: (UUID) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(link?.service.label ?? "service")?",
            isPresented: Binding(
                get: { link != nil },
                set: { if !$0 { link = nil } }
            ),
            titleVisibility: .visible,
            presenting: link
        ) { target in
            let serviceID = target.service.id
            // macOS 15 only extracts an unmodified Button as a dialog action.
            Button("Delete", role: .destructive) {
                onDelete(serviceID)
                link = nil
            }
        } message: { _ in
            Text("This will permanently remove the service and all its data.")
        }
    }
}

extension View {
    func deleteServiceConfirmation(
        link: Binding<LiveSpaceServiceLink?>,
        onDelete: @escaping (UUID) -> Void
    ) -> some View {
        modifier(DeleteServiceConfirmation(link: link, onDelete: onDelete))
    }
}
