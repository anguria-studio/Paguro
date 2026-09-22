import PaguroCore
import SwiftUI
import SwiftData

/// Stages a batch in the browser area while the existing service stays mounted.
struct AddServicesPage: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @State private var selection = ServiceSetupSelection()
    @State private var destinationID: UUID?

    private var resolvedDestinationID: UUID? {
        destinationID ?? appState.selectedSpaceID ?? spaces.first?.id
    }

    var body: some View {
        ServicePickerView(
            selection: $selection,
            allowsActions: !appState.isLocked,
            destination: Binding(
                get: { resolvedDestinationID },
                set: { destinationID = $0 }
            ),
            onSave: {
                guard let destinationID = resolvedDestinationID else { return false }
                return appState.addServices(selection.services, to: destinationID)
            }
        )
        .padding(.top, 24)
        .frame(maxWidth: 1040)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragHandle(endsEditingOnPress: true))
        .background(PaguroColor.Solid.canvas)
        .clipShape(RoundedRectangle(cornerRadius: PaguroRadius.surface, style: .continuous))
        .onChange(of: appState.selectedSpaceID) { _, id in destinationID = id }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add services")
    }
}
