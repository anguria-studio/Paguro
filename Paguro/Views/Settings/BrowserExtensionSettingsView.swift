#if !APP_STORE
import SwiftData
import SwiftUI
import PaguroCore
import WebKit

@available(macOS 15.4, *)
struct BrowserExtensionSettingsView: View {
    @Bindable var manager: BrowserExtensionManager
    @Environment(AppState.self) private var appState
    @State private var link = ""
    @State private var selection: Set<UUID> = []
    @State private var editing: BrowserExtensionRecord?
    @State private var removing: BrowserExtensionRecord?
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Browser extensions (prototype)").font(.headline)
                Text("Try Firefox extensions in selected services. Some extensions need browser features that Paguro does not provide. Desktop password-manager connections are not supported.")
                    .settingsCaption()
                Toggle("Check for extension updates daily", isOn: Binding(
                    get: { manager.automaticUpdateChecksEnabled }, set: { manager.setAutomaticUpdateChecks($0) }
                ))
                .disabled(manager.isBusy)
                HStack {
                    Text("Checks download metadata only. Installing an update needs your approval.").settingsCaption()
                    Spacer()
                    Button("Check now") { manager.checkForUpdates(force: true) }
                        .disabled(manager.records.isEmpty || manager.isBusy || manager.isCheckingUpdates)
                    if manager.isCheckingUpdates { ProgressView().controlSize(.small) }
                }
                TextField("Firefox Add-ons link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Firefox Add-ons link")
                    .disabled(manager.isBusy)
                HStack {
                    Button("Review extension") { manager.review(link: link) }
                        .disabled(link.isEmpty || manager.isBusy)
                    if manager.isBusy {
                        ProgressView().controlSize(.small)
                        if manager.isReviewing { Button("Cancel") { manager.cancelReview() } }
                    }
                }

                if let message = manager.errorMessage {
                    Text(message).foregroundStyle(.red).font(.paguroCaption).textSelection(.enabled)
                }
                if manager.libraryIsUnreadable {
                    Button("Reset extension library…") { confirmingReset = true }
                }
                if let preview = manager.preview {
                    previewContent(preview)
                }
                Divider()
                if manager.records.isEmpty {
                    Text("No extensions installed.").foregroundStyle(.secondary)
                }
                ForEach(manager.records) { record in recordRow(record) }
            }
            .padding(20)
        }
        .disabled(appState.isLocked)
        .onChange(of: link) { manager.discardPreview() }
        .onChange(of: manager.preview?.package.sha256) {
            if let preview = manager.preview {
                selection = manager.records.first { $0.slug == preview.package.slug }?.serviceIDs ?? []
            }
        }
        .sheet(item: $editing) { record in
            ExtensionAssignmentSheet(manager: manager, record: record)
        }
        .alert("Remove extension?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        )) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) {
                if let removing { manager.remove(removing.id) }
                removing = nil
            }
        } message: {
            Text("This reloads the services that use the extension. Your website sign-ins are kept.")
        }
        .alert("Reset extension library?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { manager.resetUnreadableLibrary() }
        } message: {
            Text("Paguro keeps a copy of the unreadable file and removes the saved extension packages. You can then install extensions again. Website sign-ins are kept.")
        }
        .onDisappear { manager.cancelReview() }
    }

    private func recordRow(_ record: BrowserExtensionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.name).font(.headline)
            Text("Version \(record.version). Selected services: \(record.serviceIDs.intersection(manager.assignableServiceIDs()).count).")
                .settingsCaption()
            if let release = manager.availableUpdates[record.id] {
                Label("Version \(release.version) available", systemImage: "arrow.down.circle")
                    .font(.paguroCaption).foregroundStyle(.blue)
            }
            if let message = manager.updateCheckErrors[record.id] {
                Text(message).settingsCaption()
            } else if let date = manager.updateChecks.entries[record.id.uuidString]?.checkedAt {
                Text("Last update check: \(date.formatted(date: .abbreviated, time: .shortened))").settingsCaption()
            }
            if let failure = manager.failures[record.id] {
                Text(failure).foregroundStyle(.red).font(.paguroCaption)
            }
            let problems = runtimeProblems(record.id)
            if !problems.isEmpty {
                BrowserExtensionDiagnosticDetails(messages: problems)
            }
            HStack {
                Button("Choose services") { editing = record }
                if manager.availableUpdates[record.id] != nil {
                    Button("Review update") { manager.reviewUpdate(record.id) }
                } else {
                    Button("Check for updates") { manager.checkForUpdates(force: true, ids: [record.id]) }
                        .disabled(manager.isCheckingUpdates)
                }
                if manager.optionalAccess[record.id.uuidString]?.isEmpty == false {
                    Button("Reset extra access") { manager.resetOptionalAccess(record.id) }
                        .help("Clear optional access choices for all selected services. Required access is kept.")
                }
                Button("Remove", role: .destructive) { removing = record }
            }
            .disabled(manager.isBusy)
        }
        .padding(.vertical, 4)

    }

    private func runtimeProblems(_ id: UUID) -> [String] {
        manager.runtimeIssues.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { serviceID in
            guard let issues = manager.runtimeIssues[serviceID]?[id], !issues.isEmpty else { return nil }
            let service = appState.service(id: serviceID)
            return "\(service?.label ?? "Service"): \(issues.joined(separator: "\n"))"
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: BrowserExtensionManager.Preview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let icon = preview.webExtension.icon(for: CGSize(width: 32, height: 32)) {
                    Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                }
                VStack(alignment: .leading) {
                    Text(preview.name).font(.headline)
                    Text("Version \(preview.package.version)").settingsCaption()
                }
            }
            Text("Access requested").font(.headline)
            Text("The extension can read and change the listed websites in the services you choose. Optional access needs a separate approval.")
                .settingsCaption()
            ForEach(preview.permissions, id: \.self) { permission in
                Text(permission).font(.paguroCaption).textSelection(.enabled)
            }
            ExtensionServicePicker(selection: $selection)
            Text("Installing or changing an extension reloads the affected services. Save work in those services first.")
                .settingsCaption()
            HStack {
                Button("Cancel") { manager.discardPreview() }
                Spacer()
                Button("Install in selected services") { manager.installPreview(serviceIDs: selection) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || manager.isBusy)
            }
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionAssignmentSheet: View {
    let manager: BrowserExtensionManager
    let record: BrowserExtensionRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(record.name).font(.headline)
            ScrollView { ExtensionServicePicker(selection: $selection) }
            Text("Saving reloads the services whose selection changed.").settingsCaption()
            if let message = manager.errorMessage { Text(message).foregroundStyle(.red).font(.paguroCaption) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { if manager.assign(record.id, to: selection) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(manager.isBusy || appState.isLocked)
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
        .paguroSheetAppearance()
        .onAppear { selection = record.serviceIDs }
    }
}

struct ExtensionServicePicker: View {
    @Binding var selection: Set<UUID>
    @Query(sort: \Space.sortOrder) private var spaces: [Space]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(spaces) { space in
                VStack(alignment: .leading, spacing: 6) {
                    Text(space.displayNameWithEmoji).font(.headline)
                    ForEach(space.serviceLinks.sorted { $0.sortOrder < $1.sortOrder }) { link in
                        if let service = link.liveService {
                            Toggle(service.label, isOn: Binding(
                                get: { selection.contains(service.id) },
                                set: { if $0 { selection.insert(service.id) } else { selection.remove(service.id) } }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
        // Native checkbox focus rings extend beyond the control bounds.
        .padding(6)
    }
}
#endif
