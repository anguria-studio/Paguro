import PaguroCore
import SwiftUI

/// A modal editor that stages a website without saving the workspace.
struct SetupCustomWebsiteSheet: View {
    let allowsActions: Bool
    let onChoose: (ServiceSetupDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var label = ""
    @State private var url = ""
    @State private var error: String?
    @State private var isChatApp = false
    @State private var iconDraft = ServiceIconDraft()
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a custom website")
                    .font(.title2.weight(.semibold))
                Text("Give it a name and choose the icon you’ll see in Paguro.")
                    .font(.paguroBody)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            HStack(alignment: .top, spacing: 24) {
                ServiceIconPicker(label: label.isEmpty ? "Website" : label, draft: iconDraft)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name").font(.paguroBody.weight(.medium))
                        TextField("Website name", text: $label, prompt: Text("My website"))
                            .focused($nameIsFocused)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Website address").font(.paguroBody.weight(.medium))
                        TextField(
                            "Website address", text: $url,
                            prompt: Text(verbatim: "https://example.com").foregroundStyle(.secondary)
                        )
                        .onChange(of: url) {
                            error = nil
                            iconDraft.updateURL(url)
                        }
                        Text("The website icon appears here automatically. You can also choose an image.")
                            .font(.paguroCaption)
                            .foregroundStyle(.secondary)
                    }
                    ChatAppToggle(isOn: $isChatApp)
                    if let message = error ?? iconDraft.errorMessage {
                        Text(message).font(.paguroCaption).foregroundStyle(.red)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .modifier(SetupKeyboardActivation { dismiss() })
                    .keyboardShortcut(.cancelAction)
                Button("Add website", action: selectWebsite)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .modifier(SetupKeyboardActivation(action: selectWebsite))
                    .keyboardShortcut(.defaultAction)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .paguroSheetAppearance()
        .disabled(!allowsActions)
        .onAppear { nameIsFocused = true }
        .onDisappear { iconDraft.cancel() }
        .onChange(of: allowsActions) { _, allowed in
            if !allowed { iconDraft.cancel() }
            else { iconDraft.updateURL(url) }
        }
    }

    private func selectWebsite() {
        guard allowsActions, !appState.isLocked else { return }
        switch CustomServiceInputValidator.validate(label: label, url: url) {
        case .invalid(let message): error = message
        case .valid(let label, let url):
            onChoose(ServiceSetupDraft(
                label: label, url: url,
                customIconData: iconDraft.customIconData,
                fetchedIconData: iconDraft.fetchedIcon(for: url),
                isChatApp: isChatApp
            ))
        }
    }
}
