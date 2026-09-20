import PaguroCore
import SwiftUI

/// An optional page within service selection. Select stages a draft; it does not save.
struct SetupCustomWebsiteStep: View {
    let allowsActions: Bool
    let onBack: () -> Void
    let onChoose: (ServiceSetupDraft) -> Void

    @Environment(AppState.self) private var appState
    @State private var label = ""
    @State private var url = ""
    @State private var error: String?
    @State private var iconDraft = ServiceIconDraft()
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a custom website")
                    .font(.largeTitle.weight(.semibold))
                Text("Give it a name and choose the icon you’ll see in Paguro.")
                    .font(.paguroBody)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)

            ScrollView {
                HStack(alignment: .top, spacing: 28) {
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
                        if let message = error ?? iconDraft.errorMessage {
                            Text(message).font(.paguroCaption).foregroundStyle(.red)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FirstRunFooter {
                Button("Back to services", action: onBack)
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Select website", action: selectWebsite)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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
                fetchedIconData: iconDraft.fetchedIcon(for: url)
            ))
        }
    }
}
