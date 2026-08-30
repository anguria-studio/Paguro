import SwiftUI
import SwiftData
import BlattaCore

extension UnifiedRailView {
    @ViewBuilder
    var railCreationMenu: some View {
        Button("Add Service…") {
            appState.showAddService = true
        }
        .disabled(selectedSpaceID == nil)

        Button("Add Workspace…") {
            appState.showAddSpace = true
        }
    }

    @ViewBuilder
    func workspaceContextMenu(for space: Space) -> some View {
        WorkspaceContextMenuItems(
            space: space,
            allowsDelete: liveSpaces.count > 1,
            onAddService: {
                selectedSpaceID = space.id
                appState.showAddService = true
            },
            onEdit: { editingSpace = space },
            onDelete: { confirmingDeleteSpace = space }
        )
    }

    @ViewBuilder
    func serviceContextMenu(for link: LiveSpaceServiceLink) -> some View {
        Button("Edit Service…") {
            editingService = link.service
        }

        Toggle("Mute Notifications", isOn: Binding(
            get: { link.service.isMuted },
            set: { newValue in
                appState.setServiceMuted(newValue, for: link.service.id)
            }
        ))

        if let media = appState.webViewPool.mediaCaptureStates[link.service.id],
           media.micActive || media.micMuted {
            Button(media.micMuted ? "Unmute Microphone" : "Mute Microphone") {
                appState.webViewPool.setMicrophoneMuted(
                    !media.micMuted,
                    for: link.service.id
                )
            }
        }

        Divider()

        Button("Open in Safari") {
            openInDefaultBrowser(link.service)
        }

        Divider()

        if appState.webViewPool.hasWebView(for: link.service.id) {
            Button("Hibernate") {
                appState.webViewPool.hibernate(link.service.id)
                if selectedServiceID == link.service.id {
                    selectedServiceID = nil
                }
            }
        }

        Divider()
        Button("Change Icon…") {
            appState.pickCustomIcon(for: link.service.id)
        }
        if link.service.customIconData != nil {
            Button("Reset Icon") {
                appState.resetIcon(for: link.service.id)
            }
        }
        Divider()
        Menu("Move to Workspace") {
            let targets = eligibleSpaces(for: link.service)
            ForEach(targets) { space in
                Button {
                    appState.moveService(
                        linkID: link.id,
                        to: space.id,
                        followToSpace: false
                    )
                } label: {
                    Text(space.displayNameWithEmoji)
                }
                .accessibilityLabel(space.name)
            }
            if !targets.isEmpty {
                Divider()
            }
            Button("New Workspace…") {
                movingToNewSpace = link
            }
        }
        Button("Remove from this workspace") {
            removeFromSpace(link: link)
        }
        Divider()
        Button("Delete service entirely", role: .destructive) {
            confirmingDelete = link
        }
    }

    /// Opens the live page in the default browser, with the home URL as fallback.
    private func openInDefaultBrowser(_ service: ServiceInstance) {
        let liveURL = appState.webViewPool.liveWebView(for: service.id)?.url
        let target = liveURL ?? URL(string: service.url)
        if let target {
            WebViewCoordinator.openExternally(target)
        }
    }

    /// Returns spaces where the service does not have a live membership.
    private func eligibleSpaces(for service: ServiceInstance) -> [Space] {
        let memberIDs = Set(
            allLinks
                .compactMap(\.liveEnds)
                .filter { $0.service.id == service.id }
                .map { $0.space.id }
        )
        let eligible = Set(SpaceMove.eligibleSpaceIDs(
            allSpaceIDs: spaces.map(\.id),
            memberSpaceIDs: memberIDs
        ))
        return spaces.filter { eligible.contains($0.id) }
    }

    /// Fixes selection before `AppState` removes the membership.
    private func removeFromSpace(link: LiveSpaceServiceLink) {
        if selectedServiceID == link.service.id && selectedSpaceID == link.space.id {
            selectedServiceID = nil
        }
        appState.removeLink(link.id)
    }
}
