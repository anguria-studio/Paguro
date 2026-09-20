import PaguroCore
import SwiftUI

struct FirstRunWizardView: View {
    let setup: FirstRunSetup?
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @State private var selection = ServiceSetupSelection()

    var body: some View {
        Group {
            if appState.showAddService {
                FirstRunServicePicker(selection: $selection, allowsActions: allowsActions)
            } else {
                FirstRunHomeView(setup: setup, allowsActions: allowsActions)
            }
        }
    }
}

private struct FirstRunServicePicker: View {
    @Binding var selection: ServiceSetupSelection
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var category = "All services"
    @State private var showsCustomWebsite = false
    @State private var saveError: String?
    @FocusState private var searchIsFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 14)]
    private let catalog = ServiceCatalog.shared

    private var entries: [ServiceCatalogEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.entries.filter {
            (category == "All services" || $0.category == category)
                && (query.isEmpty || "\($0.name) \($0.category) \($0.description)"
                    .localizedStandardContains(query))
        }.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    private var customDrafts: [ServiceSetupDraft] {
        selection.services.filter { $0.catalogEntryID == nil }
    }

    var body: some View {
        Group {
            if showsCustomWebsite {
                SetupCustomWebsiteStep(
                    allowsActions: allowsActions,
                    onBack: { showsCustomWebsite = false },
                    onChoose: { draft in
                        guard allowsActions else { return }
                        selection.toggle(draft)
                        showsCustomWebsite = false
                    }
                )
            } else {
                catalogContent
            }
        }
        .frame(maxWidth: 1040)
        .padding(.top, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragHandle())
        .background(PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity))
        .disabled(!allowsActions)
    }

    private var catalogContent: some View {
        VStack(spacing: 0) {
            header
            filters
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(entries) { entry in
                        let draft = ServiceSetupDraft(
                            id: entry.id, label: entry.name, url: entry.url,
                            catalogEntryID: entry.id, userAgent: entry.userAgent
                        )
                        ServiceSetupTile(
                            draft: draft, subtitle: entry.category,
                            isSelected: selection.contains(entry.id)
                        ) {
                            selection.toggle(draft)
                        }
                        .help(entry.description)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)

                if entries.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                if !customDrafts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom websites")
                            .font(.headline)
                        ForEach(customDrafts) { draft in
                            HStack(spacing: 12) {
                                customIcon(for: draft)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(draft.label)
                                    Text(draft.url)
                                        .font(.paguroCaption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Remove") { selection.toggle(draft) }
                                    .accessibilityLabel("Remove \(draft.label)")
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            footer
        }
        .onAppear { searchIsFocused = true }
    }

    @ViewBuilder
    private func customIcon(for draft: ServiceSetupDraft) -> some View {
        if let data = draft.customIconData ?? draft.fetchedIconData,
           let image = ServiceIconImageProcessor.displayImage(from: data) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        } else {
            Text(ServiceIconPalette.initial(for: draft.label))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(ServiceIconPalette.color(for: draft.label), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 2 of 2")
                    .font(.paguroCaption)
                    .foregroundStyle(.secondary)
                Text("Choose your services")
                    .font(.largeTitle.weight(.semibold))
                Text("Pick the services you use. You’ll sign in to each one after setup.")
                    .font(.paguroBody)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var filters: some View {
        HStack(spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search services", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
            }
            .padding(10)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Picker("Category", selection: $category) {
                Text("All services").tag("All services")
                ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 170)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            if let saveError {
                Text(saveError)
                    .font(.paguroCaption)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }
            HStack(spacing: 16) {
                Button("Back") { appState.showAddService = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add a custom website") { showsCustomWebsite = true }
                    .buttonStyle(.link)
                Spacer()
                Text("\(selection.services.count) selected")
                    .font(.paguroCaption)
                    .foregroundStyle(.secondary)
                Button(addTitle) { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.services.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
    }

    private var addTitle: String {
        let count = selection.services.count
        return count == 1 ? "Add 1 service" : "Add \(count) services"
    }

    private func finish() {
        guard allowsActions else { return }
        if !appState.addSetupServices(selection.services) {
            saveError = "Paguro could not save your services. Your selection is ready to try again."
        }
    }
}

private struct ServiceSetupTile: View {
    let draft: ServiceSetupDraft
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var icon: NSImage?
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: PaguroRadius.surface)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let brand = NSImage(named: "brand-\(draft.catalogEntryID ?? "")") {
                        Image(nsImage: brand).resizable().scaledToFit()
                    } else if let icon {
                        Image(nsImage: icon).resizable().scaledToFit()
                    } else {
                        Text(String(draft.label.prefix(1)))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
                Text(draft.label)
                    .font(.paguroBody.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.paguroCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Color.primary.opacity(isSelected ? 0.10 : (isHovering ? 0.07 : 0.04))))
            .overlay {
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.6 : 0.12),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(12)
                    .accessibilityHidden(true)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(draft.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Press to \(isSelected ? "deselect" : "select") this service")
        .task(id: draft.catalogEntryID) {
            if let id = draft.catalogEntryID {
                icon = await CatalogIconCache.shared.icon(for: id)
            }
        }
    }
}
