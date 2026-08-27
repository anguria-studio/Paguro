import SwiftUI
import SwiftData
import AtollCore

struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @State private var searchText = ""
    @State private var selectedTab: AddServiceTab = .catalog
    @State private var selectedSpaceID: UUID
    @State private var customURL = ""
    @State private var customLabel = ""
    @State private var customIconData: Data?
    @State private var iconWebsiteURL = ""
    @State private var urlError: String?

    enum AddServiceTab: String, CaseIterable {
        case catalog = "Browse"
        case custom = "Custom URL"
    }

    init(spaceID: UUID) {
        _selectedSpaceID = State(initialValue: spaceID)
    }

    private var liveSpaces: [Space] {
        spaces.filter { $0.modelContext != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("", selection: $selectedTab) {
                ForEach(AddServiceTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Add service by")
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if liveSpaces.count > 1 {
                Picker("Workspace", selection: $selectedSpaceID) {
                    ForEach(liveSpaces) { space in
                        Text(space.displayNameWithEmoji)
                            .tag(space.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            if !AppCapabilities.passkeysSupported {
                passkeyNotice
            }

            switch selectedTab {
            case .catalog:
                catalogContent
            case .custom:
                customURLContent
            }
        }
        .frame(width: 520, height: 480)
    }

    /// Calm, non-blocking heads-up that passkey sign-in won't work in-app yet.
    /// Shown for both catalog and custom adds. Gated by AppCapabilities so it
    /// disappears in one edit once the WebAuthn browser entitlement is granted.
    private var passkeyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(AppCapabilities.passkeyUnavailableNotice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AtollRadius.control))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppCapabilities.passkeyUnavailableNotice)
    }

    private var header: some View {
        HStack {
            Text("Add a service")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var catalogContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search services…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AtollRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: AtollRadius.control)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            CatalogGridView(
                searchText: searchText,
                spaceID: selectedSpaceID,
                onAdd: { dismiss() }
            )
        }
    }

    private var customURLContent: some View {
        Form {
            TextField("Label", text: $customLabel, prompt: Text("My Service"))
                .textFieldStyle(.roundedBorder)

            TextField("URL", text: $customURL, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: customURL) { urlError = nil }

            if let error = urlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            ServiceIconEditor(
                label: customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Service"
                    : customLabel,
                serviceURL: customURL,
                customIconData: $customIconData,
                websiteURL: $iconWebsiteURL
            )

            Button("Add Service") {
                addCustomService()
            }
            .disabled(customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func addCustomService() {
        switch CustomServiceInputValidator.validate(label: customLabel, url: customURL) {
        case .invalid(let error):
            urlError = error
            return
        case .valid(let label, let url):
            addCustomService(label: label, url: url)
        }
    }

    private func addCustomService(label: String, url: String) {
        guard appState.addService(
            label: label,
            url: url,
            customIconData: customIconData,
            to: selectedSpaceID
        ) != nil else {
            urlError = "Atoll could not save this service. Try again."
            return
        }

        dismiss()
    }
}
