import SwiftUI
import SwiftData
import BlattaCore
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

struct SettingsView: View {
    #if canImport(Sparkle)
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }
    #else
    init() {}
    #endif

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "lock")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private var aboutTab: some View {
        #if canImport(Sparkle)
        AboutSettingsView(updater: updater)
        #else
        AboutSettingsView()
        #endif
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    // Settings is its own scene (`Settings { … }` in BlattaApp), separate from
    // `Window("Blatta", id: "main")`. The recovery sheet is only attached to
    // the main window, so setting the recovery picker state from here alone
    // would attach it behind Settings — or, if the user had closed the main
    // window (the MenuBarExtra keeps the app alive), attach it to nothing at
    // all, latching the flag `true` with no sheet visible. `openWindow(id:)`
    // on a `Window` (a singleton scene, not a `WindowGroup`) brings that
    // existing window to the front rather than creating a duplicate — or
    // reopens it if it was closed — per SwiftUI's `OpenWindowAction` docs:
    // "If the targeted scene is a Window, the system orders it to the front."
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Dock & Menu Bar") {
                Picker("Show Blatta in", selection: Binding(
                    get: { appModel.presenceController.mode },
                    set: { mode in
                        appModel.setPresenceMode(mode)
                    }
                )) {
                    Text("Dock only").tag(AppPresenceMode.dock)
                    Text("Menu bar only").tag(AppPresenceMode.menuBar)
                    Text("Both").tag(AppPresenceMode.both)
                }

                Toggle("Show badge count on Dock icon", isOn: Binding(
                    get: { appState.badgeManager.showBadgeCountInDock },
                    set: { appState.setShowBadgeCountInDock($0) }
                ))
            }

            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { appState.appearanceMode },
                    set: { appState.setAppearanceMode($0) }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Window glass", selection: Binding(
                    get: { appState.liquidGlassStyle },
                    set: { appState.setLiquidGlassStyle($0) }
                )) {
                    ForEach(ShellGlassStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .help("Changes the native Liquid Glass style behind the main window shell.")

                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { appState.liquidGlassIntensity },
                            set: { appState.setLiquidGlassIntensity($0) }
                        ),
                        in: 0...1
                    ) {
                        Text("Shell transparency")
                    }

                    Text("\(Int((appState.liquidGlassIntensity * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .help("Controls how much of the desktop appears through the Blatta shell. This control does not change web pages.")

                HStack {
                    Spacer()
                    Button("Reset Glass Lab") {
                        appState.resetGlassLab()
                    }
                    .controlSize(.small)
                }

                Picker("Layout", selection: Binding(
                    get: { appState.railLayout },
                    set: { appState.setRailLayout($0) }
                )) {
                    ForEach(RailLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }

                // The two-rail layouts show every workspace in a rail of their
                // own, which leaves this setting nothing to choose.
                if RailBarPresentationPolicy.offersWorkspaceView(
                    hasWorkspaceRail: appState.railLayout.showsBothRails
                ) {
                    Picker("Workspace view", selection: Binding(
                        get: { appState.workspaceViewMode },
                        set: { appState.setWorkspaceViewMode($0) }
                    )) {
                        Text("Current workspace").tag(WorkspaceViewMode.current)
                        Text("All workspaces").tag(WorkspaceViewMode.all)
                    }
                    .help("Shows one workspace, or every workspace with its services grouped under its name.")
                }

                // A rail row is full width, so its name costs no space.
                // Icons-only is offered where the services are in the bar.
                if RailBarPresentationPolicy.offersIconsOnly(
                    servicesInBar: appState.railLayout.servicesInBar
                ) {
                    Toggle("Show icons only", isOn: Binding(
                        get: { appState.railBarIconsOnly },
                        set: { appState.setRailBarIconsOnly($0) }
                    ))
                    .help("Keeps the service icons in the top bar and removes their names. A workspace with an icon shows the icon alone; one without an icon keeps its name.")
                }
            }

            // Every one of these settings shapes the collapsed rail on the
            // left, whether it holds the services or the workspaces. The
            // top-bar layout has no rail for them to shape.
            if appState.railLayout.hasSideRail {
                Section("Icon Rail") {
                    LabeledContent("Size") {
                        Slider(
                            value: Binding(
                                get: { appState.iconRailBaseSize },
                                set: { appState.setIconRailBaseSize($0) }
                            ),
                            in: DockIconSizing.minimumBaseSize...DockIconSizing.maximumBaseSize,
                            step: 1
                        )
                        .frame(width: 240)
                        .accessibilityLabel("Icon rail size")
                        .accessibilityValue("\(Int(appState.iconRailBaseSize.rounded())) points")
                    }

                    LabeledContent("Magnification") {
                        Slider(
                            value: Binding(
                                get: { appState.iconRailMagnification },
                                set: { appState.setIconRailMagnification($0) }
                            ),
                            in: DockIconSizing.minimumMagnification...DockIconSizing.maximumMagnification,
                            step: 0.01
                        )
                        .frame(width: 240)
                        .accessibilityLabel("Icon rail magnification")
                        .accessibilityValue(
                            appState.iconRailMagnification == 0
                                ? "Off"
                                : "\(Int((appState.iconRailMagnification * 100).rounded())) percent"
                        )
                    }

                    Picker("Vertical position", selection: Binding(
                        get: { appState.iconRailPosition },
                        set: { appState.setIconRailPosition($0) }
                    )) {
                        ForEach(DockRailPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("These settings apply when the sidebar is collapsed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Web Content") {
                Toggle("Accept cookie banners automatically", isOn: Binding(
                    get: { appState.preferencesStore.autoDismissCookieBanners },
                    set: { appState.setAutoDismissCookieBanners($0) }
                ))
                Text("This accepts consent pop-ups for you. That includes advertising and tracking cookies, so turn it off to answer each site's banner yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Performance") {
                Toggle("Hibernate idle background services", isOn: Binding(
                    get: { appState.autoHibernateIdleEnabled },
                    set: { value in
                        appState.setAutoHibernateIdleEnabled(value)
                    }
                ))

                if appState.autoHibernateIdleEnabled {
                    Picker("After", selection: Binding(
                        get: { appState.autoHibernateIdleMinutes },
                        set: { appState.setAutoHibernateIdleMinutes($0) }
                    )) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                }

                Text("Frees the memory and CPU of a service you haven't opened in a while, releasing its process until you return. Chat apps (Slack, Teams, WhatsApp, and the like) stay live so their notifications still arrive the instant a message lands, even when many services are open. A hibernated service still refreshes its unread badge every few minutes, though that count only climbs until you open it again. Mark any service \"Keep Loaded\" to exempt it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { appModel.presenceController.isLaunchAtLoginEnabled },
                    set: { appModel.presenceController.setLaunchAtLogin($0) }
                ))
            }

            Section("Data") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore from a backup")
                        Text("Blatta keeps a copy of your workspaces and services before each update.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore from a backup…") {
                        AppDelegate.prepareToShowWindow()
                        openWindow(id: "main")
                        appState.storeRecovery.isShowingPicker = true
                    }
                }
            }

            Section("Accessibility") {
                Picker("Default zoom", selection: Binding(
                    get: { appState.defaultZoom },
                    set: { appState.setDefaultZoom($0) }
                )) {
                    ForEach(Self.zoomLevels, id: \.self) { level in
                        Text("\(Int((level * 100).rounded()))%").tag(level)
                    }
                }
                Text("Applies to every service. Zoom a single service with ⌘- / ⌘+ to override this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static let zoomLevels: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
}

struct NotificationSettingsView: View {
    @Query private var services: [ServiceInstance]
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            authorizationWarningSection

            Section("Presentation") {
                Toggle("Show macOS notifications", isOn: Binding(
                    get: {
                        appModel.notificationRouteSettings.isSystemRouteEnabled
                    },
                    set: { appModel.setSystemNotificationRouteEnabled($0) }
                ))

                Toggle("Show island alerts on notched displays", isOn: Binding(
                    get: {
                        appModel.notificationRouteSettings.isIslandRouteEnabled
                    },
                    set: { appModel.setIslandNotificationRouteEnabled($0) }
                ))

                Text("On a display without a notch, island alerts use macOS notifications. Service mute and Do Not Disturb apply to both routes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if DEBUG
                Button("Show Test Island Alert") {
                    appModel.showIslandPreview(for: activeService)
                }
                .disabled(
                    !appModel.notificationRouteSettings.isIslandRouteEnabled
                )
                #endif
            }

            Section {
                Toggle("Do Not Disturb", isOn: Binding(
                    get: { appState.doNotDisturb },
                    set: { appState.doNotDisturb = $0 }
                ))
                Text("Silences notification alerts. Unread badges remain visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            scheduledDNDSection

            Section("Per-Service") {
                if services.isEmpty {
                    Text("No services added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    serviceTable
                    Text("Turning a service off silences its alerts and badge — mute is the master switch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var activeService: ServiceInstance? {
        guard let serviceID = appState.selectedServiceID else { return nil }
        return services.first { $0.id == serviceID }
    }

    /// Names a missing macOS notification permission.
    ///
    /// Without this row a denied permission is invisible: Blatta still builds
    /// each notification, `UNUserNotificationCenter` still accepts it, and
    /// macOS drops it without a banner.
    @ViewBuilder
    private var authorizationWarningSection: some View {
        if let warning = NotificationAuthorizationPresentation.warning(
            for: appState.notificationManager.authorizationState
        ) {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(warning.title)
                            .font(.headline)
                        Text(warning.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(warning.actionTitle) {
                            openNotificationSettings()
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(warning.title)
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: NotificationAuthorizationPresentation.systemSettingsURLString
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var serviceTable: some View {
        let grouped = NotificationGrouping.grouped(spaces: spaces, services: services)
        return Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Service")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gridColumnAlignment(.leading)
                Text("On").frame(width: 44)
                Text("macOS").frame(width: 52)
                Text("Badge").frame(width: 52)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ForEach(grouped.groups) { group in
                if grouped.showsHeaders {
                    GridRow {
                        Text(headerTitle(group))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                            .gridCellColumns(4)
                    }
                }

                ForEach(group.services) { service in
                    serviceRow(service)
                }
            }
        }
    }

    /// A space's optional emoji and name, or "Ungrouped" for services in no space. The
    /// same service can appear under several space headers; every row binds to
    /// the same model object, so their toggles stay in sync.
    private func headerTitle(_ group: NotificationGrouping.Group) -> String {
        guard let space = group.space else { return "Ungrouped" }
        return space.displayNameWithEmoji
    }

    @ViewBuilder
    private func serviceRow(_ service: ServiceInstance) -> some View {
        GridRow {
            Text(service.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            Toggle("", isOn: enabledBinding(service))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Notifications for \(service.label)")

            Toggle("", isOn: macOSBinding(service))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(
                    service.isMuted
                        || !appModel.notificationRouteSettings.isSystemRouteEnabled
                )
                .accessibilityLabel("macOS notifications for \(service.label)")

            Toggle("", isOn: badgeBinding(service))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(service.isMuted)
                .accessibilityLabel("Badge count for \(service.label)")
        }
    }

    /// Master switch: on means not muted. Muting silences banners and badge.
    private func enabledBinding(_ service: ServiceInstance) -> Binding<Bool> {
        Binding(
            get: { !service.isMuted },
            set: { enabled in
                service.isMuted = !enabled
                save("toggle mute for \(service.label)")
                appState.refreshBadgeState(for: service.id)
            }
        )
    }

    private func macOSBinding(_ service: ServiceInstance) -> Binding<Bool> {
        Binding(
            get: { service.notifiesOSEffective },
            set: { enabled in
                service.osNotificationsEnabled = enabled
                save("toggle macOS notifications for \(service.label)")
            }
        )
    }

    private func badgeBinding(_ service: ServiceInstance) -> Binding<Bool> {
        Binding(
            get: { service.showBadge },
            set: { enabled in
                service.showBadge = enabled
                save("toggle badge for \(service.label)")
                appState.refreshBadgeState(for: service.id)
            }
        )
    }

    @ViewBuilder
    private var scheduledDNDSection: some View {
        Section("Quiet Hours") {
            Toggle("Do Not Disturb on a schedule", isOn: Binding(
                get: { appState.scheduledDNDEnabled },
                set: { appState.setScheduledDNDEnabled($0) }
            ))

            if appState.scheduledDNDEnabled {
                DatePicker("From", selection: timeBinding(
                    get: { appState.dndStartMinutes },
                    set: { appState.setDNDStartMinutes($0) }
                ), displayedComponents: .hourAndMinute)

                DatePicker("To", selection: timeBinding(
                    get: { appState.dndEndMinutes },
                    set: { appState.setDNDEndMinutes($0) }
                ), displayedComponents: .hourAndMinute)
            }

            Text("Silences notification banners during these hours. Unread badges remain visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Bridges a minutes-since-midnight value to the Date a time-only DatePicker
    /// expects. The supplied setter owns persistence and runtime updates.
    private func timeBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = get() / 60
                comps.minute = get() % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
        )
    }

    private func save(_ context: String) {
        modelContext.saveOrRollback(reason: "save setting (\(context))")
    }
}

struct PrivacySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Service Icons") {
                Toggle("Ask Google for icons Blatta can't find", isOn: Binding(
                    get: { appState.preferencesStore.googleFaviconFallbackEnabled },
                    set: { value in
                        appState.setGoogleFaviconFallbackEnabled(value)
                    }
                ))

                Text("Blatta fetches each service's icon from that service's own site. When a site serves none, this asks Google for one, which tells Google the hostname — including a private or self-hosted one. Off by default; services without an icon show their initial instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App Lock") {
                Toggle("Require Touch ID or password", isOn: Binding(
                    get: { appState.appLockEnabled },
                    set: { appState.setAppLockEnabled($0) }
                ))

                if appState.appLockEnabled {
                    Toggle("Lock on launch", isOn: Binding(
                        get: { appState.lockOnLaunch },
                        set: { appState.setLockOnLaunch($0) }
                    ))
                    Toggle("Lock when the Mac sleeps or the screen locks", isOn: Binding(
                        get: { appState.lockOnSleep },
                        set: { appState.setLockOnSleep($0) }
                    ))
                }

                Text("Uses Touch ID, with your login password as a fallback. Lock immediately from the File menu (⇧⌘L).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Content Blocking") {
                Toggle("Block ads and trackers", isOn: Binding(
                    get: { appState.contentBlockingEnabled },
                    set: { appState.setContentBlockingEnabled($0) }
                ))

                Text("Blocks known ad and tracking domains across your services. It won't remove ads a site serves from its own domain, so YouTube and Facebook ads still get through.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Hide annoyances", isOn: Binding(
                    get: { appState.annoyanceBlockingEnabled },
                    set: { appState.setAnnoyanceBlockingEnabled($0) }
                ))

                Text("Hides cookie notices, newsletter pop-ups, floating share bars, and similar clutter. It's more aggressive than ad blocking and can occasionally hide something you wanted, so it's off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Camera & Microphone") {
                Picker("Camera", selection: Binding(
                    get: { appState.mediaPermissions.defaultCameraPolicy },
                    set: { appState.mediaPermissions.setDefaultCameraPolicy($0) }
                )) {
                    ForEach(MediaPermissionPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Microphone", selection: Binding(
                    get: { appState.mediaPermissions.defaultMicrophonePolicy },
                    set: { appState.mediaPermissions.setDefaultMicrophonePolicy($0) }
                )) {
                    ForEach(MediaPermissionPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                Text("The default for new services. \"Ask\" prompts the first time a service wants your camera or microphone and remembers the answer. Set a single service's own rule in its Edit sheet. Mute every live microphone at once with ⇧⌘M.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsView: View {
    #if canImport(Sparkle)
    let updater: SPUUpdater
    #endif

    private let upstreamURL = URL(string: "https://github.com/nicojan/Chorus")!
    private let upstreamLicenseURL = URL(string: "https://github.com/nicojan/Chorus/blob/main/LICENSE")!
    private let authorURL = URL(string: "https://nicojan.com/")!
    private let blocklistURL = URL(string: "https://github.com/hagezi/dns-blocklists")!
    private let annoyanceListURL = URL(string: "https://easylist.to/")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    appIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blatta")
                            .font(.title2)
                            .bold()
                        Text(AppVersion.current)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                #if canImport(Sparkle)
                CheckForUpdatesView(updater: updater)
                #endif
            }

            Section {
                Link("Chorus upstream project", destination: upstreamURL)
                Link("Upstream MIT license", destination: upstreamLicenseURL)
            }

            Section("Content blocking") {
                Text("Ad and tracker blocking uses the HaGezi DNS blocklist. Annoyance hiding uses Fanboy's Annoyance List from EasyList.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("HaGezi blocklists (GPL-3.0)", destination: blocklistURL)
                Link("EasyList / Fanboy Annoyance List", destination: annoyanceListURL)
            }

            Section {
                HStack(spacing: 4) {
                    Text("Blatta is based on Chorus by")
                    Link("Nico Jan", destination: authorURL)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
        }
    }
}

/// Formats the app version for display. Kept as a pure helper (fed a bundle's
/// info dictionary) so it can be unit-tested without a running app.
enum AppVersion {
    static func string(from info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    static var current: String {
        string(from: Bundle.main.infoDictionary)
    }
}

/// Groups services by space for the per-service notifications list. Pure (fed
/// plain arrays) so the ordering and bucketing rules can be unit-tested without
/// a running app or a model container.
///
/// Rules: spaces appear in the caller's order (the view sorts by `sortOrder`);
/// within a space, services follow their link `sortOrder`; a service in several
/// spaces appears under each; services in no space fall into a trailing
/// "Ungrouped" bucket (`space == nil`), sorted by label. Spaces with no
/// services are skipped. When nothing is grouped — no spaces have members —
/// `showsHeaders` is false and a single flat, headerless bucket holds every
/// service, matching the pre-grouping layout.
enum NotificationGrouping {
    struct Group: Identifiable {
        /// The space, or `nil` for the ungrouped / flat bucket.
        let space: Space?
        let services: [ServiceInstance]

        var id: String { space?.id.uuidString ?? "ungrouped" }
    }

    struct Result {
        let groups: [Group]
        /// False only when no space has members, so the view renders a plain
        /// flat list with no space headers.
        let showsHeaders: Bool
    }

    static func grouped(spaces: [Space], services: [ServiceInstance]) -> Result {
        var spaceGroups: [Group] = []
        for space in spaces {
            let members = space.serviceLinks
                // Skip dangling links (a link whose Space or ServiceInstance was
                // deleted): materializing `.service` on a faulted model traps.
                // `.modelContext` is nil once deleted and safe to read.
                .filter { $0.modelContext != nil && $0.service.modelContext != nil }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.service)
            if !members.isEmpty {
                spaceGroups.append(Group(space: space, services: members))
            }
        }

        // No space has members → flat, headerless list of everything.
        guard !spaceGroups.isEmpty else {
            let flat = services.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            return Result(groups: [Group(space: nil, services: flat)], showsHeaders: false)
        }

        let ungrouped = services
            .filter { $0.spaceLinks.isEmpty }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        var groups = spaceGroups
        if !ungrouped.isEmpty {
            groups.append(Group(space: nil, services: ungrouped))
        }
        return Result(groups: groups, showsHeaders: true)
    }
}
