import SwiftUI
import SwiftData
import BlattaCore
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct BlattaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel: AppModel

    private var appState: AppState { appModel.appState }

    #if canImport(Sparkle)
    /// Owns the Sparkle updater for the app's lifetime: drives the
    /// "Check for Updates…" command and runs scheduled background checks.
    private let updaterController: SPUStandardUpdaterController
    #endif

    init() {
        let appModel = AppModel()
        _appModel = State(initialValue: appModel)
        #if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
        appModel.connect(to: appDelegate)
    }

    var body: some Scene {
        Window("Blatta", id: "main") {
            ContentView()
                .environment(appState)
                .environment(appModel)
                .modelContainer(appState.modelContainer)
                .preferredColorScheme(appState.appearanceColorScheme)
                .onDisappear {
                    appModel.saveWindowState()
                }
        }
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // The custom credits keep the upstream source link visible.
            CommandGroup(replacing: .appInfo) {
                Button("About Blatta") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [.credits: Self.aboutCredits]
                    )
                }
            }

            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            #endif

            CommandGroup(replacing: .newItem) {
                Button("Add Service…") {
                    appState.showAddService = true
                }
                .keyboardShortcut("n", modifiers: .command)
                // With no space selected the sheet has nowhere to add the
                // service and renders empty and un-dismissable, so disable ⌘N
                // until a space exists (the seeded app always has one; this
                // covers the transient no-space state).
                .disabled(appState.selectedSpaceID == nil)

                Button("Add Workspace…") {
                    appState.showAddSpace = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Quick Switcher") {
                    appState.showQuickSwitcher.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button(appState.doNotDisturb ? "Turn Off Do Not Disturb" : "Do Not Disturb") {
                    appState.doNotDisturb.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Lock Now") {
                    appState.lock()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!appState.appLockEnabled)

                Button(MicrophoneMutePresentation.menuTitle(
                    activeCount: appState.webViewPool.activeMicrophoneCount
                )) {
                    appState.mediaPermissions.muteActiveMicrophones()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(appState.webViewPool.activeMicrophoneCount == 0)
            }

            KeyboardShortcutCommands(
                selectedServiceID: Binding(
                    get: { appState.selectedServiceID },
                    set: { appState.selectedServiceID = $0 }
                ),
                selectedSpaceID: Binding(
                    get: { appState.selectedSpaceID },
                    set: { appState.selectedSpaceID = $0 }
                ),
                getServicesForSpace: { spaceID in
                    servicesForSpace(spaceID)
                },
                getSpaces: {
                    allSpaces()
                }
            )

            CommandGroup(after: .toolbar) {
                Button("Back") {
                    appState.goBackInActiveService()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!appState.webViewState.canGoBack)

                Button("Forward") {
                    appState.goForwardInActiveService()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!appState.webViewState.canGoForward)

                Button("Reload") {
                    appState.reloadActiveService()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    appState.adjustActiveServiceZoom(by: 1.1)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    appState.adjustActiveServiceZoom(by: 1.0 / 1.1)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    appState.resetActiveServiceZoom()
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Find…") {
                    appState.findInPageVisible = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        // "Dock only" removes the menu-bar item. When the user drags the item
        // off the menu bar, the preference follows: Blatta keeps the Dock icon
        // so the app stays reachable.
        MenuBarExtra(isInserted: Binding(
            get: { appModel.presenceController.mode.showsMenuBarItem },
            set: { inserted in
                let mode = appModel.presenceController.mode
                if !inserted, mode != .dock {
                    appModel.setPresenceMode(.dock)
                } else if inserted, mode == .dock {
                    appModel.setPresenceMode(.both)
                }
            }
        )) {
            MenuBarView()
                .environment(appState)
                .environment(appModel)
                .modelContainer(appState.modelContainer)
                .preferredColorScheme(appState.appearanceColorScheme)
        } label: {
            // The status item glyph is a template asset, so macOS tints it for
            // the light and dark menu bar. The status item uses the intrinsic
            // asset size and ignores a SwiftUI frame, so the asset itself is
            // 16 points, the size of a standard menu-bar glyph.
            Image("MenuBarIcon")
                .accessibilityLabel("Blatta")
        }
        .menuBarExtraStyle(.window)

        Settings {
            #if canImport(Sparkle)
            SettingsView(updater: updaterController.updater)
                .environment(appState)
                .environment(appModel)
                .modelContainer(appState.modelContainer)
                .preferredColorScheme(appState.appearanceColorScheme)
            #else
            SettingsView()
                .environment(appState)
                .environment(appModel)
                .modelContainer(appState.modelContainer)
                .preferredColorScheme(appState.appearanceColorScheme)
            #endif
        }
    }

    @MainActor
    private func servicesForSpace(_ spaceID: UUID) -> [ServiceInstance] {
        // Route through AppState's implementation, which guards against
        // dangling links (reading `link.space`/`.service` on a deleted model
        // traps). This is called from keyboard shortcuts, so an unguarded copy
        // could crash on a keystroke.
        appState.servicesForSpace(spaceID)
    }

    @MainActor
    private func allSpaces() -> [Space] {
        let context = appState.modelContainer.mainContext
        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to fetch spaces: \(error.localizedDescription)")
            return []
        }
    }

    /// Creates the credits text for the About panel.
    private static var aboutCredits: NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center

        let credits = NSMutableAttributedString(
            string: "A native workspace for the web services that you use.\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: centred
            ]
        )
        credits.append(
            NSAttributedString(
                string: "Based on Chorus",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.linkColor,
                    .link: UpstreamProjectLink.url,
                    .paragraphStyle: centred
                ]
            )
        )
        return credits
    }
}

// MARK: - Sparkle auto-update ("Check for Updates…" menu command)
//
// Defined here (a file that is part of the Blatta target) rather than a
// standalone file, so it compiles when Sparkle is resolved. Gated on
// canImport(Sparkle) so the project still builds before the package is present.

#if canImport(Sparkle)

/// Publishes whether the updater can currently check for updates, so the menu
/// item can enable/disable itself reactively.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// The "Check for Updates…" menu command. The intermediate view exists so the
/// disabled state binds correctly (a known SwiftUI menu quirk).
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
#endif
