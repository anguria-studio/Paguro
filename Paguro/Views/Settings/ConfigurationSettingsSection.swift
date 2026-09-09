import SwiftUI
import SwiftData
import PaguroCore

struct ConfigurationSettingsSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppState.self) private var appState
    @State private var pendingArchive: ConfigurationArchive?
    @Query private var existingWorkspaces: [Space]
    @Query private var existingServices: [ServiceInstance]
    @State private var importMode = ConfigurationImportMode.add
    @State private var applyPreferences = true
    @State private var resultMessage: String?

    var body: some View {
        Section("Configuration") {
            HStack {
                Button("Export Configuration…", action: exportConfiguration)
                Button("Import Configuration…", action: chooseImport)
            }
            .disabled(appState.isLocked)
            Text("Transfer workspaces, services, and preferences to another Mac. Login sessions are not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: Binding(
            get: { pendingArchive != nil },
            set: { if !$0 { pendingArchive = nil } }
        )) {
            if let archive = pendingArchive { importPreview(archive) }
        }
        .alert("Configuration", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func importPreview(_ archive: ConfigurationArchive) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Configuration").font(.title2.bold())
            Text("\(archive.workspaces.count) workspaces and \(archive.services.count) services in this file.")
            Picker("Import mode", selection: $importMode) {
                Text("Add to Current").tag(ConfigurationImportMode.add)
                Text("Replace Current").tag(ConfigurationImportMode.replace)
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(archive.workspaces, id: \.id) { workspace in
                        Text("\(workspace.name) — \(workspace.serviceIDs.count) services")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            Text(importMode == .replace
                 ? "Replace all \(existingWorkspaces.count) current workspaces and \(existingServices.count) services with this file. Their local login sessions will be removed. Imported services start signed out."
                 : "Existing workspaces and accounts stay as they are. Imported services start signed out. Importing the same file again adds another copy.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Apply app preferences from this file", isOn: $applyPreferences)
            Text("This includes appearance, notifications, app lock, and camera and microphone rules. macOS permissions and launch at login stay on this Mac.")
                .fixedSize(horizontal: false, vertical: true)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { pendingArchive = nil }
                    .keyboardShortcut(.cancelAction)
                Button(importMode == .replace ? "Replace and Import" : "Import",
                       role: importMode == .replace ? .destructive : nil) { performImport(archive) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.isLocked)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func exportConfiguration() {
        do {
            let data = try appModel.exportConfigurationData()
            _ = try ConfigurationFileAccess.export(data)
        } catch { resultMessage = error.localizedDescription }
    }

    private func chooseImport() {
        do {
            pendingArchive = try ConfigurationFileAccess.chooseImport()
            applyPreferences = true
            importMode = .add
        } catch { resultMessage = error.localizedDescription }
    }

    private func performImport(_ archive: ConfigurationArchive) {
        do {
            try appModel.importConfiguration(archive, applyPreferences: applyPreferences, mode: importMode)
            pendingArchive = nil
            resultMessage = "Imported \(archive.workspaces.count) workspaces and \(archive.services.count) services. Sign in to each imported service to use it."
        } catch {
            pendingArchive = nil
            resultMessage = error.localizedDescription
        }
    }
}
