import PaguroCore
import SwiftUI
import SwiftData

struct FirstRunWizardView: View {
    let setup: FirstRunSetup?
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = ServiceSetupSelection()
    @State private var hasLoadedWorkspaceName = false
    @Query(sort: \Space.sortOrder) private var spaces: [Space]

    var body: some View {
        ZStack {
            if appState.showAddService {
                ServicePickerView(selection: $selection, allowsActions: allowsActions)
                    .transition(pageTransition(from: 24))
            } else {
                FirstRunHomeView(setup: setup, allowsActions: allowsActions)
                    .transition(pageTransition(from: -24))
            }
        }
        .animation(.easeInOut(duration: PaguroMotion.setupStepSeconds), value: appState.showAddService)
        .clipped()
        .padding(.top, 52)
        .frame(maxWidth: 1040)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragHandle(endsEditingOnPress: true))
        .background(PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity))
        .onAppear {
            guard !hasLoadedWorkspaceName else { return }
            hasLoadedWorkspaceName = true
            let target = spaces.first { $0.id == appState.selectedSpaceID } ?? spaces.first
            selection.workspaceName = target?.name ?? WorkspaceName.defaultValue
        }
    }

    private func pageTransition(from offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: offset))
    }
}
