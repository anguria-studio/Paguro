import PaguroCore
import SwiftUI

/// One footer stays mounted outside the animated setup pages.
struct FirstRunNavigationView: View {
    let currentStep: FirstRunStep
    let allowsActions: Bool
    let canContinue: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onSelectStep: (FirstRunStep) -> Void

    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    @FocusState private var primaryActionIsFocused: Bool
    @State private var importMessage: String?

    var body: some View {
        FirstRunFooter(currentStep: currentStep, canContinue: canContinue, onSelect: onSelectStep) {
            if currentStep == .welcome {
                Button("Import configuration…", action: importConfiguration)
                    .buttonStyle(.link)
                    .modifier(SetupKeyboardActivation(action: importConfiguration))
                    .help("Import a configuration from another Mac")
            } else {
                Button("Back", action: onBack)
                    .modifier(SetupKeyboardActivation(action: onBack))
                    .keyboardShortcut(.cancelAction)
            }
        } trailing: {
            Button(nextTitle, action: onNext)
                .buttonStyle(.borderedProminent)
                .modifier(SetupKeyboardActivation(action: onNext))
                .keyboardShortcut(.return, modifiers: currentStep == .welcome ? [] : .command)
                .focused($primaryActionIsFocused)
                .disabled(currentStep != .welcome && !canContinue)
        }
        .disabled(!allowsActions)
        .task(id: currentStep) {
            // The catalog owns search focus; the other pages start at their primary action.
            primaryActionIsFocused = false
            guard currentStep != .workspace else { return }
            await Task.yield()
            guard !Task.isCancelled, allowsActions else { return }
            primaryActionIsFocused = true
        }
        .alert("Import Configuration", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var nextTitle: String {
        switch currentStep {
        case .welcome: "Choose your services"
        case .workspace: "Continue"
        case .appearance: "Create workspace"
        }
    }

    private func importConfiguration() {
        guard allowsActions, !appState.isLocked else { return }
        do {
            guard let archive = try ConfigurationFileAccess.chooseImport() else { return }
            try appModel.importConfiguration(archive, applyPreferences: true, mode: .add)
            importMessage = "Imported \(archive.workspaces.count) workspaces and \(archive.services.count) services. Sign in to each imported service to use it."
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
