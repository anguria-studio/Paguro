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
    @State private var hasOpenedCatalog = false
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
                onNext: advance,
                onSelectStep: navigate
            )
        }
        .onChange(of: appState.showAddService, initial: true) { _, showing in
            if showing {
                hasOpenedCatalog = true
            } else {
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
            if appState.showAddService || hasOpenedCatalog {
                // Keep the catalog mounted across every step to retain filters and scroll position.
                ServicePickerView(
                    selection: $selection, allowsActions: allowsActions && currentStep == .workspace,
                    onEditorPresentationChange: { isEditingService = $0 }
                )
                .accessibilityElement(children: currentStep == .workspace ? .contain : .ignore)
                .opacity(currentStep == .workspace ? 1 : 0)
                .offset(x: reduceMotion || currentStep == .workspace ? 0 : (currentStep == .welcome ? 24 : -24))
                .allowsHitTesting(currentStep == .workspace)
                .accessibilityHidden(currentStep != .workspace)
                .transition(pageTransition(from: 24))
            }
            if currentStep == .appearance {
                FirstRunAppearanceView(allowsActions: allowsActions, saveError: saveError)
                    .transition(pageTransition(from: 24))
            } else if currentStep == .welcome {
                FirstRunHomeView(setup: setup, allowsActions: allowsActions)
                    .transition(pageTransition(from: -24))
            }
        }
    }

    private func navigate(to step: FirstRunStep) {
        guard allowsActions, !appState.isLocked, !isEditingService,
              currentStep.canNavigate(to: step, canCreateWorkspace: selection.canCreateWorkspace) else { return }
        saveError = nil
        showsAppearance = step == .appearance
        appState.showAddService = step != .welcome
    }

    private func goBack() {
        navigate(to: currentStep == .appearance ? .workspace : .welcome)
    }

    private func advance() {
        switch currentStep {
        case .welcome: navigate(to: .workspace)
        case .workspace: navigate(to: .appearance)
        case .appearance: finish()
        }
    }

    private func finish() {
        guard allowsActions, !appState.isLocked, !isEditingService, showsAppearance, selection.canCreateWorkspace else { return }
        if !appState.addSetupServices(selection.services, workspaceName: selection.workspaceName) {
            saveError = "Paguro could not save your services. Your selection is ready to try again."
        }
    }

    private func pageTransition(from offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: offset))
    }
}
