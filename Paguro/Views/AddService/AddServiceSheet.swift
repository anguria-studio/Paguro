import SwiftUI
import SwiftData
import PaguroCore

struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @State private var searchText = ""
    @State private var selectedTab: AddServiceTab = .catalog
    @State private var selectedSpaceID: UUID?
    @State private var customURL = ""
    @State private var customLabel = ""
    @State private var iconDraft = ServiceIconDraft()
    @State private var urlError: String?

    enum AddServiceTab: String, CaseIterable {
        case catalog = "Browse"
        case custom = "Custom URL"
    }

    init(spaceID: UUID?) {
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
                            .tag(Optional(space.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
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
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: PaguroRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: PaguroRadius.control)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                ServiceIconPicker(
                    label: customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Service" : customLabel,
                    draft: iconDraft
                )

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.paguroCaption)
                            .foregroundStyle(.secondary)
                        TextField("Service name", text: $customLabel, prompt: Text("My Service"))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(.paguroCaption)
                            .foregroundStyle(.secondary)
                        TextField("Service address", text: $customURL, prompt: Text("https://example.com"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customURL) {
                                urlError = nil
                                iconDraft.updateURL(customURL)
                            }
                    }
                }
            }

            if let error = urlError {
                Text(error)
                    .font(.paguroCaption)
                    .foregroundStyle(.red)
            }

            if let error = iconDraft.errorMessage {
                Text(error)
                    .font(.paguroCaption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Add Service") {
                    addCustomService()
                }
                .disabled(customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { iconDraft.updateURL(customURL) }
        .onDisappear { iconDraft.cancel() }
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
            customIconData: iconDraft.customIconData,
            fetchedIconData: iconDraft.fetchedIcon(for: url),
            to: selectedSpaceID
        ) != nil else {
            urlError = "Paguro could not save this service. Try again."
            return
        }

        dismiss()
    }
}
