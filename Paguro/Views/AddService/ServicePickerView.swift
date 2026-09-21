import PaguroCore
import SwiftUI
import SwiftData

struct ServicePickerView: View {
    @Binding var selection: ServiceSetupSelection
    let allowsActions: Bool
    var destination: Binding<UUID?>? = nil
    var onSave: (() -> Bool)? = nil
    var onEditorPresentationChange: ((Bool) -> Void)? = nil

    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    private var isFirstWorkspace: Bool { destination == nil }
    private var liveSpaces: [Space] { spaces.filter { $0.modelContext != nil } }

    @Environment(AppState.self) private var appState
    @State private var scrollToCustomWebsite = 0
    @State private var search = ""
    @State private var category = "All services"
    @State private var categoryKeyboardControl = SetupChoiceMenu.KeyboardControl()
    @State private var workspaceKeyboardControl = SetupChoiceMenu.KeyboardControl()
    @State private var showsCustomWebsite = false
    @State private var showsNewWorkspace = false
    @State private var saveError: String?
    private enum InputField: Hashable { case workspaceName, destination, search, category, services, customWebsite }
    @State private var activeServiceID: String?
    @State private var showsGridKeyboardFocus = false
    @State private var gridColumnCount = 1
    @State private var usesWideHeader = false
    @State private var focusAfterCustom: InputField = .customWebsite
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

    private var navigation: SetupGridNavigation {
        SetupGridNavigation(
            sections: [customDrafts.map(\.id), entries.map(\.id)], columns: gridColumnCount
        )
    }

    var body: some View {
        catalogContent
            .disabled(!allowsActions)
            .sheet(isPresented: $showsCustomWebsite, onDismiss: {
                focusedField = focusAfterCustom
            }) {
                SetupCustomWebsiteSheet(
                    allowsActions: allowsActions,
                    onChoose: { draft in
                        guard allowsActions, !appState.isLocked else { return }
                        selection.toggle(draft)
                        search = ""
                        category = "All services"
                        scrollToCustomWebsite += 1
                        activeServiceID = draft.id
                        focusAfterCustom = .services
                        showsCustomWebsite = false
                    }
                )
            }
            .onChange(of: showsCustomWebsite || showsNewWorkspace) { _, presented in
                onEditorPresentationChange?(presented)
            }
            .onChange(of: allowsActions) { _, allowed in focusedField = allowed ? .search : nil }
            .onChange(of: navigation) { activeServiceID = navigation.retainedID(activeServiceID) }
            .sheet(isPresented: $showsNewWorkspace, onDismiss: {
                focusedField = .destination
            }) {
                if let destination {
                    SpaceEditorSheet(
                        editingSpace: nil,
                        selectedSpaceID: destination,
                        activatesCreatedWorkspace: false
                    )
                    .disabled(!allowsActions)
                }
            }
            .onChange(of: focusedField) { _, field in
                if field == .services {
                    activeServiceID = navigation.retainedID(activeServiceID)
                }
            }
            .background {
                SetupInputMethodObserver(
                    isEnabled: allowsActions && !showsCustomWebsite && !showsNewWorkspace,
                    onChange: { showsGridKeyboardFocus = $0 }
                )
            }
    }

    private var catalogContent: some View {
        VStack(spacing: 0) {
            header
            if !isFirstWorkspace {
                destinationPicker
            }
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
                                            isSelected: selection.contains(draft.id),
                                            isKeyboardFocused: showsGridKeyboardFocus
                                                && focusedField == .services && activeServiceID == draft.id
                                        ) {
                                            showsGridKeyboardFocus = false
                                            activeServiceID = draft.id
                                            focusedField = .services
                                            selection.toggle(draft)
                                        }
                                        .id(draft.id)
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
                                            isSelected: selection.contains(entry.id),
                                            isKeyboardFocused: showsGridKeyboardFocus
                                                && focusedField == .services && activeServiceID == entry.id
                                        ) {
                                            showsGridKeyboardFocus = false
                                            activeServiceID = entry.id
                                            focusedField = .services
                                            selection.toggle(draft)
                                        }
                                        .id(entry.id)
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
                .focusable(navigation.firstID != nil, interactions: .edit)
                .focused($focusedField, equals: .services)
                .focusEffectDisabled()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Services")
                .accessibilityHint("Use arrow keys to move between services. Press Space or Return to select.")
                .onGeometryChange(for: Int.self) { geometry in
                    max(1, Int((geometry.size.width - 64 + 14) / (140 + 14)))
                } action: { gridColumnCount = $0 }
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { key in
                    guard SetupKeyboardActivation.accepts(key.modifiers) else { return .ignored }
                    moveGridFocus(key.key)
                    return .handled
                }
                .onKeyPress(keys: [.space, .return]) { key in
                    guard SetupKeyboardActivation.accepts(key.modifiers) else { return .ignored }
                    toggleActiveService()
                    return .handled
                }
                .onChange(of: activeServiceID) { _, id in
                    if focusedField == .services, let id { proxy.scrollTo(id) }
                }
                .onChange(of: focusedField) { _, field in
                    if field == .services, let id = activeServiceID { proxy.scrollTo(id) }
                }
                .onChange(of: scrollToCustomWebsite) { proxy.scrollTo("service-list-top", anchor: .top) }
            }
            if !isFirstWorkspace { footer }
        }
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.size.width >= 900
        } action: { usesWideHeader = $0 }
        .task {
            // Wait for the new page to enter the focus hierarchy before choosing its input.
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = .search
        }
    }

    private var header: some View {
        // AnyLayout preserves the editor and its focus when the window resizes.
        let layout = usesWideHeader
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return layout {
            VStack(alignment: .leading, spacing: 6) {
                Text(isFirstWorkspace ? "Set up your first workspace" : "Choose your services")
                    .font(.largeTitle.weight(.semibold))
                Text(isFirstWorkspace
                    ? "A workspace keeps related services together for work, personal use, or a project."
                    : "Select the services you want to add to your workspace.")
                    .font(.paguroBody)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isFirstWorkspace {
                workspaceNameField
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var workspaceNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace name")
                .font(.paguroBody.weight(.medium))
            TextField("Workspace name", text: $selection.workspaceName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focusedField, equals: .workspaceName)
                .onSubmit { focusedField = nil }
                .onChange(of: selection.workspaceName) { saveError = nil }
        }
        .frame(width: usesWideHeader ? 240 : 320, alignment: .leading)
    }

    @ViewBuilder
    private var destinationPicker: some View {
        if let destination {
            HStack(spacing: 12) {
                Text("Add to")
                    .font(.paguroBody.weight(.medium))
                SetupChoiceMenu(
                    categories: liveSpaces.map { $0.id.uuidString },
                    labels: Dictionary(uniqueKeysWithValues: liveSpaces.map { ($0.id.uuidString, $0.displayNameWithEmoji) }),
                    accessibilityName: "Workspace",
                    action: .init(title: "New workspace…", perform: {
                        guard allowsActions, !appState.isLocked else { return }
                        focusedField = nil
                        showsNewWorkspace = true
                    }),
                    keyboardControl: workspaceKeyboardControl,
                    selection: Binding(
                        get: { destination.wrappedValue?.uuidString ?? "" },
                        set: { destination.wrappedValue = UUID(uuidString: $0) }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
                .focusable(interactions: .edit)
                .focused($focusedField, equals: .destination)
                .onKeyPress(keys: [.space, .return, .downArrow, .upArrow]) { key in
                    guard SetupKeyboardActivation.accepts(key.modifiers) else { return .ignored }
                    workspaceKeyboardControl.open()
                    return .handled
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                searchField
                categoryMenu
                Spacer(minLength: 0)
                customWebsiteButton
            }
            VStack(alignment: .leading, spacing: 12) {
                searchField
                HStack(spacing: 12) {
                    categoryMenu
                    Spacer(minLength: 0)
                    customWebsiteButton
                }
            }
        }
        .font(.paguroBody)
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search services", text: $search)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .search)
                .onSubmit { enterGrid() }
                .onKeyPress(.downArrow) {
                    enterGrid()
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .frame(width: 256, height: 36)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var categoryMenu: some View {
        SetupChoiceMenu(
            categories: ["All services"]
                + (selection.customWebsites.isEmpty ? [] : ["Custom websites"])
                + catalog.categories,
            keyboardControl: categoryKeyboardControl,
            selection: $category
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .focusable(interactions: .edit)
        .focused($focusedField, equals: .category)
        .onKeyPress(keys: [.space, .return, .downArrow, .upArrow]) { key in
            guard SetupKeyboardActivation.accepts(key.modifiers) else { return .ignored }
            categoryKeyboardControl.open()
            return .handled
        }
        .onChange(of: category) { focusedField = nil }
    }

    private var customWebsiteButton: some View {
        Button(action: openCustomWebsite) {
            Label("Custom website", systemImage: "plus")
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .modifier(SetupKeyboardActivation(action: openCustomWebsite))
        .focused($focusedField, equals: .customWebsite)
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let saveError {
                Text(saveError)
                    .font(.paguroCaption)
                    .foregroundStyle(.red)
                    .padding(.vertical, 12)
            }
            Divider()
            HStack {
                cancelButton
                Spacer()
                saveButton
            }
            .controlSize(.large)
            .frame(minHeight: 36)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { appState.showAddService = false }
            .modifier(SetupKeyboardActivation { appState.showAddService = false })
            .keyboardShortcut(.cancelAction)
    }

    private var saveButton: some View {
        Button("Add services", action: finish)
            .buttonStyle(.borderedProminent)
            .modifier(SetupKeyboardActivation(action: finish))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(selection.services.isEmpty || !liveSpaces.contains { $0.id == destination?.wrappedValue })
    }

    private func openCustomWebsite() {
        guard allowsActions else { return }
        focusedField = nil
        focusAfterCustom = .customWebsite
        showsCustomWebsite = true
    }

    private func enterGrid() {
        guard let first = navigation.firstID else { return }
        showsGridKeyboardFocus = true
        activeServiceID = first
        focusedField = .services
    }

    private func moveGridFocus(_ key: KeyEquivalent) {
        showsGridKeyboardFocus = true
        let direction: SetupGridNavigation.Direction
        switch key {
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        case .upArrow: direction = .up
        default: direction = .down
        }
        activeServiceID = navigation.destination(from: activeServiceID, direction: direction)
    }

    private func toggleActiveService() {
        guard allowsActions, !showsCustomWebsite, !showsNewWorkspace, let id = activeServiceID else { return }
        showsGridKeyboardFocus = true
        if let draft = customDrafts.first(where: { $0.id == id }) {
            selection.toggle(draft)
        } else if let entry = entries.first(where: { $0.id == id }) {
            selection.toggle(ServiceSetupDraft(
                id: entry.id, label: entry.name, url: entry.url,
                catalogEntryID: entry.id, userAgent: entry.userAgent
            ))
        }
    }

    private func finish() {
        guard allowsActions, !appState.isLocked, !showsCustomWebsite, !showsNewWorkspace else { return }
        let saved = onSave?()
            ?? appState.addSetupServices(selection.services, workspaceName: selection.workspaceName)
        if !saved {
            saveError = "Paguro could not save your services. Your selection is ready to try again."
        }
    }
}

private struct ServiceSetupTile: View {
    let draft: ServiceSetupDraft
    let subtitle: String
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let action: () -> Void

    @Environment(AppState.self) private var appState
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
            .background(shape.fill(Color.primary.opacity(
                isSelected ? 0.10 : (isHovering ? 0.07 : (appState.liquidGlassStyle == .off ? 0 : 0.04))
            )))
            .background {
                if appState.liquidGlassStyle == .off { shape.fill(PaguroColor.Solid.card) }
            }
            .overlay {
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.6 : 0.12),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            .overlay {
                if isKeyboardFocused {
                    shape.inset(by: 5)
                        .strokeBorder(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
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
        .focusable(false)
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
