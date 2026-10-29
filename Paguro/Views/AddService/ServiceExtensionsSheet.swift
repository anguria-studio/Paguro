#if !APP_STORE
import SwiftUI
import PaguroCore

@available(macOS 15.4, *)
struct ServiceExtensionsSheet: View {
    let manager: BrowserExtensionManager
    let service: ServiceInstance
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Extensions for \(service.label)").font(.headline)
            Text("Changes apply immediately and reload this service. Install extensions in Settings > Extensions.")
                .settingsCaption()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(manager.records) { record in
                        Toggle(record.name, isOn: Binding(
                            get: { manager.records.first { $0.id == record.id }?.serviceIDs.contains(service.id) == true },
                            set: { enabled in
                                var ids = record.serviceIDs
                                if enabled { ids.insert(service.id) } else { ids.remove(service.id) }
                                manager.assign(record.id, to: ids)
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(6)
            }
            if manager.records.contains(where: { $0.serviceIDs.contains(service.id) }) {
                Picker("Extension compatibility", selection: Binding(
                    get: { manager.profile(for: service.id) },
                    set: { manager.setProfile($0, for: service.id) }
                )) {
                    Text("Standard").tag(ExtensionRuntimeProfile.standard)
                    Text("Firefox").tag(ExtensionRuntimeProfile.firefox)
                }
                Text("Firefox changes the browser identity for this service and its extensions. It overrides Mobile view and custom browser identity while selected.")
                    .settingsCaption()
            }
            if let message = manager.errorMessage { Text(message).foregroundStyle(.red).font(.paguroCaption) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 420, height: 420)
        .disabled(manager.isBusy || appState.isLocked)
        .paguroSheetAppearance()
    }
}
#endif
