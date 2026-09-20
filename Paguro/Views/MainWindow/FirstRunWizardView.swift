import PaguroCore
import SwiftUI
import SwiftData

struct FirstRunWizardView: View {
    let setup: FirstRunSetup?
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = ServiceSetupSelection()
    @State private var hasLoadedWorkspaceName = false
    @Query(sort: \Space.sortOrder) private var spaces: [Space]

    var body: some View {
        VStack(spacing: 24) {
            FirstRunProgress(isChoosingServices: appState.showAddService)
                .padding(.horizontal, 32)
            ZStack {
                if appState.showAddService {
                    FirstRunServicePicker(selection: $selection, allowsActions: allowsActions)
                        .transition(pageTransition(from: 24))
                } else {
                    FirstRunHomeView(setup: setup, allowsActions: allowsActions)
                        .transition(pageTransition(from: -24))
                }
            }
            .animation(.easeInOut(duration: PaguroMotion.setupStepSeconds), value: appState.showAddService)
            .clipped()
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

    private func pageTransition(from offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: offset))
    }
}

private struct FirstRunServicePicker: View {
    @Binding var selection: ServiceSetupSelection
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollToCustomWebsite = 0
    @State private var search = ""
    @State private var category = "All services"
    @State private var showsCustomWebsite = false
    @State private var saveError: String?
    private enum InputField: Hashable { case workspaceName, search }
    @FocusState private var focusedField: InputField?

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
        guard category == "All services" || category == "Custom websites" else { return [] }
        return selection.matchingCustomWebsites(search: search)
    }

    var body: some View {
        ZStack {
            // Keep the catalog alive so returning from custom entry retains its scroll position.
            catalogContent
                .opacity(showsCustomWebsite ? 0 : 1)
                .offset(x: showsCustomWebsite && !reduceMotion ? -24 : 0)
                .allowsHitTesting(!showsCustomWebsite)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(showsCustomWebsite)
                .disabled(showsCustomWebsite)
            if showsCustomWebsite {
                SetupCustomWebsiteStep(
                    allowsActions: allowsActions,
                    onBack: { showsCustomWebsite = false },
                    onChoose: { draft in
                        guard allowsActions else { return }
                        selection.toggle(draft)
                        search = ""
                        category = "All services"
                        scrollToCustomWebsite += 1
                        showsCustomWebsite = false
                    }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 24)))
            }
        }
        .animation(.easeInOut(duration: PaguroMotion.setupStepSeconds), value: showsCustomWebsite)
        .disabled(!allowsActions)
        .onChange(of: showsCustomWebsite) { _, isShowing in
            focusedField = isShowing ? nil : .search
        }
    }

    private var catalogContent: some View {
        VStack(spacing: 0) {
            header
            workspaceNameField
            filters
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if !customDrafts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Custom websites")
                                    .font(.headline)
                                LazyVGrid(columns: columns, spacing: 14) {
                                    ForEach(customDrafts) { draft in
                                        ServiceSetupTile(
                                            draft: draft, subtitle: "Custom website",
                                            isSelected: selection.contains(draft.id)
                                        ) {
                                            selection.toggle(draft)
                                        }
                                        .help(draft.url)
                                    }
                                }
                            }
                        }
                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                if !customDrafts.isEmpty {
                                    Text("Catalog").font(.headline)
                                }
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
                            }
                        }
                        if entries.isEmpty && customDrafts.isEmpty {
                            ContentUnavailableView.search(text: search)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .id("service-list-top")
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
                .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
                .onChange(of: scrollToCustomWebsite) { proxy.scrollTo("service-list-top", anchor: .top) }
            }
            footer
        }
        .onAppear { focusedField = .search }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your first workspace")
                    .font(.largeTitle.weight(.semibold))
                Text("A workspace keeps related services together for work, personal use, or a project.")
                    .font(.paguroBody)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var workspaceNameField: some View {
        HStack(spacing: 12) {
            Text("Workspace name")
                .font(.paguroBody.weight(.medium))
            TextField("Workspace name", text: $selection.workspaceName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(maxWidth: 320)
                .focused($focusedField, equals: .workspaceName)
                .onSubmit { focusedField = nil }
                .onChange(of: selection.workspaceName) { saveError = nil }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search services", text: $search)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .search)
            }
            .padding(.horizontal, 12)
            .frame(width: 256, height: 36)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            Menu {
                Picker("Category", selection: $category) {
                    Text("All services").tag("All services")
                    if !selection.customWebsites.isEmpty {
                        Text("Custom websites").tag("Custom websites")
                    }
                    ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(category)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12)
            .frame(width: 170, height: 36)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("Category")
            .accessibilityValue(category)
            .onChange(of: category) { focusedField = nil }
            Spacer(minLength: 0)
            Button {
                focusedField = nil
                showsCustomWebsite = true
            } label: {
                Label("Custom website", systemImage: "plus")
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .font(.paguroBody)
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let saveError {
                Text(saveError)
                    .font(.paguroCaption)
                    .foregroundStyle(.red)
                    .padding(.vertical, 12)
            }
            FirstRunFooter {
                Button("Back") { appState.showAddService = false }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Create workspace") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.services.isEmpty || WorkspaceName.normalized(selection.workspaceName) == nil)
            }
        }
    }

    private func finish() {
        guard allowsActions else { return }
        if !appState.addSetupServices(selection.services, workspaceName: selection.workspaceName) {
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
                    if let data = draft.customIconData,
                       let image = ServiceIconImageProcessor.displayImage(from: data) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else if let brand = NSImage(named: "brand-\(draft.catalogEntryID ?? "")") {
                        Image(nsImage: brand).resizable().scaledToFit()
                    } else if let data = draft.fetchedIconData,
                              let image = ServiceIconImageProcessor.displayImage(from: data) {
                        Image(nsImage: image).resizable().scaledToFit()
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
                    .lineLimit(1)
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
                    .contentTransition(.opacity)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(12)
                    .accessibilityHidden(true)
            }
            .contentShape(shape)
            .animation(.easeInOut(duration: PaguroMotion.setupSelectionSeconds), value: isSelected)
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
