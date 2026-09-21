import PaguroCore
import SwiftUI
import SwiftData

struct FirstRunWizardView: View {
    let setup: FirstRunSetup?
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = ServiceSetupSelection()
    @State private var showsAppearance = false
    @State private var saveError: String?
    @State private var hasLoadedWorkspaceName = false
    @State private var isEditingService = false
    @Query(sort: \Space.sortOrder) private var spaces: [Space]

    private var currentStep: FirstRunStep {
        appState.showAddService ? (showsAppearance ? .appearance : .workspace) : .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            pages
                .animation(.easeInOut(duration: PaguroMotion.setupStepSeconds), value: appState.showAddService)
                .animation(.easeInOut(duration: PaguroMotion.setupStepSeconds), value: showsAppearance)
                .clipped()
            FirstRunNavigationView(
                currentStep: currentStep,
                allowsActions: allowsActions && !isEditingService,
                canContinue: selection.canCreateWorkspace,
                onBack: goBack,
                onNext: advance
            )
        }
        .onChange(of: appState.showAddService) { _, showing in
            if !showing {
                showsAppearance = false
                isEditingService = false
                saveError = nil
            }
        }
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

    private var pages: some View {
        ZStack {
            if appState.showAddService {
                ZStack {
                    // Keep the catalog mounted so Back preserves filters and scroll position.
                    ServicePickerView(
                        selection: $selection, allowsActions: allowsActions && !showsAppearance,
                        onEditorPresentationChange: { isEditingService = $0 }
                    )
                    .accessibilityElement(children: showsAppearance ? .ignore : .contain)
                    .opacity(showsAppearance ? 0 : 1)
                    .allowsHitTesting(!showsAppearance)
                    .accessibilityHidden(showsAppearance)
                    if showsAppearance {
                        FirstRunAppearanceView(allowsActions: allowsActions, saveError: saveError)
                            .transition(pageTransition(from: 24))
                    }
                }
                .transition(pageTransition(from: 24))
            } else {
                FirstRunHomeView(setup: setup, allowsActions: allowsActions)
                    .transition(pageTransition(from: -24))
            }
        }
    }

    private func goBack() {
        guard allowsActions, !appState.isLocked, !isEditingService else { return }
        saveError = nil
        if showsAppearance {
            showsAppearance = false
        } else {
            appState.showAddService = false
        }
    }

    private func advance() {
        guard allowsActions, !appState.isLocked, !isEditingService else { return }
        switch currentStep {
        case .welcome:
            appState.showAddService = true
        case .workspace:
            guard selection.canCreateWorkspace else { return }
            saveError = nil
            showsAppearance = true
        case .appearance:
            finish()
        }
    }

    private func finish() {
        guard allowsActions, !appState.isLocked, showsAppearance, selection.canCreateWorkspace else { return }
        if !appState.addSetupServices(selection.services, workspaceName: selection.workspaceName) {
            saveError = "Paguro could not save your services. Your selection is ready to try again."
        }
    }

    private func pageTransition(from offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: offset))
    }
}
