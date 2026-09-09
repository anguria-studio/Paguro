import PaguroCore
import SwiftData
import SwiftUI

struct MenuBarIconLabel: View {
    @Query private var services: [ServiceInstance]
    let appState: AppState

    private var allMuted: Bool {
        NotificationMutePresentation.allServicesMuted(
            serviceMuteStates: services.map(\.isEffectivelyMuted),
            globalMute: appState.notificationRuntime.isDoNotDisturbActive()
        )
    }

    var body: some View {
        // A template asset carries its own size and alpha into the native status item.
        Image(allMuted ? "MenuBarIconMuted" : "MenuBarIcon")
            .accessibilityLabel(allMuted ? "Paguro, all services muted" : "Paguro")
    }
}
