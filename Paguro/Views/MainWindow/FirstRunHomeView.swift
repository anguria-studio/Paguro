import AppKit
import PaguroCore
import SwiftUI

/// The window before the user has a service.
///
/// It replaces an empty rail, an empty header, and one line of gray text. The
/// screen states what Paguro is, carries the two setup decisions that are
/// otherwise only in System Settings and the Settings window, and offers the
/// one action that ends first run.
///
/// The screen holds one prominent button. A tour, a dashboard, and a carousel
/// were all considered and left out: the user has one thing to do here.
struct FirstRunHomeView: View {
    /// Which setup rows apply on this Mac, or nil for none.
    let setup: FirstRunSetup?
    /// False while App Lock holds the window, so no action can run under the
    /// lock screen.
    let allowsActions: Bool

    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var primaryActionIsFocused: Bool

    /// True while macOS is deciding, so the button cannot be pressed twice.
    @State private var isRequestingPermission = false
    /// The result of an import, or nil when none has run.
    @State private var importMessage: String?

    /// The reading width of the column. A wider column makes the sentence run
    /// across the window and separates the title from the button under it.
    private static let columnWidth: CGFloat = 380
    private static let appIconSize: CGFloat = 72
    /// The bundled Paguro mark. The asset is light and dark aware, and the
    /// Notification Test catalog tile draws the same one.
    private static let appIconAsset = "brand-notification-test"

    private var authorizationState: NotificationAuthorizationState {
        appState.notificationManager.authorizationState
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaguroRadius.surface, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 22) {
            header
            if let setup { setupCard(setup) }
            actions
        }
        .padding(32)
        .frame(width: Self.columnWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // VoiceOver reads the title, the sentence, the rows, the primary
        // button, and the import line in that order, which is the order they
        // are written in.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Paguro")
        // A drag anywhere on the glass moves the window. The handle sits behind
        // the content and in front of the fill, so every control keeps its own
        // clicks. `NoticeStrip` uses the same order.
        .background(WindowDragHandle())
        .background(PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity))
        .onAppear { primaryActionIsFocused = true }
        .alert("Import Configuration", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(Self.appIconAsset)
                .resizable()
                .frame(width: Self.appIconSize, height: Self.appIconSize)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to Paguro")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PaguroColor.Text.primary)

                Text("Your web apps in one native window. Each service keeps its own sign-in, and notifications arrive like any Mac app.")
                    .font(.paguroBody)
                    .foregroundStyle(PaguroColor.Text.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Setup rows

    /// The grouped card with the two setup decisions.
    ///
    /// The card is left out when neither row applies, so the screen never shows
    /// an empty surface.
    private func setupCard(_ setup: FirstRunSetup) -> some View {
        VStack(spacing: 0) {
            if setup.showsNotificationRow {
                notificationRow
            }
            if setup.showsNotificationRow, setup.showsIslandRow {
                Divider().padding(.leading, 42)
            }
            if setup.showsIslandRow {
                islandRow
            }
        }
        .background { cardSurface }
        .overlay { cardShape.strokeBorder(borderColor, lineWidth: borderWidth) }
        .clipShape(cardShape)
    }

    private var notificationRow: some View {
        setupRow(
            systemImage: "bell.badge",
            title: "Notifications",
            message: "Let your services alert you"
        ) {
            notificationControl
        }
    }

    @ViewBuilder
    private var notificationControl: some View {
        switch authorizationState {
        case .notDetermined:
            // A permission macOS has never been asked about can still be asked
            // for in the app. Once macOS holds a decision it never asks again,
            // so the only way back is System Settings.
            Button("Allow") {
                Task {
                    isRequestingPermission = true
                    await appState.notificationManager.requestAuthorization()
                    isRequestingPermission = false
                }
            }
            .disabled(isRequestingPermission || !allowsActions)
        case .authorized:
            rowState("On")
        case .unknown:
            // The row does not appear in this state. The branch keeps the
            // switch complete.
            EmptyView()
        case .denied, .provisional, .unavailable:
            Button("Off in System Settings") {
                openNotificationSettings()
            }
            .buttonStyle(.link)
            .font(.paguroCaption)
            .disabled(!allowsActions)
        }
    }

    private var islandRow: some View {
        setupRow(
            systemImage: "rectangle.topthird.inset.filled",
            title: "Island alerts",
            message: "Show alerts beside the notch"
        ) {
            Toggle(
                "Island alerts",
                isOn: Binding(
                    get: { appModel.notificationRouteSettings.isIslandRouteEnabled },
                    set: { appModel.setIslandNotificationRouteEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!allowsActions)
        }
    }

    /// One row: a symbol, a title, a one-line description, and its control.
    ///
    /// VoiceOver reads the symbol, the title, and the description as one
    /// element, and reaches the control beside it separately.
    private func setupRow<Control: View>(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: PaguroTypeSize.body, weight: .semibold))
                    .foregroundStyle(PaguroColor.Text.primary)
                Text(message)
                    .font(.paguroCaption)
                    .foregroundStyle(PaguroColor.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(message)")

            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// A state that the user cannot change here, such as a granted permission.
    private func rowState(_ text: String) -> some View {
        Text(text)
            .font(.paguroCaption.weight(.medium))
            .foregroundStyle(PaguroColor.Text.secondary)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Add your first service") {
                guard allowsActions else { return }
                appState.showAddService = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Return activates it, and keyboard focus starts here. Command-N
            // stays with the File menu item, which works from any window state.
            .keyboardShortcut(.defaultAction)
            .focused($primaryActionIsFocused)
            .disabled(!allowsActions)

            Button("Or import a configuration from another Mac") {
                importConfiguration()
            }
            .buttonStyle(.link)
            .font(.paguroCaption)
            .disabled(!allowsActions)
        }
    }

    /// Reads a configuration file and adds it.
    ///
    /// The Settings import offers a preview with an Add or Replace choice. This
    /// screen has nothing to replace, because it appears only when no service
    /// exists, so the file is added and the result is reported. The model owns
    /// the import, so the view reaches no store.
    private func importConfiguration() {
        // The lock screen draws over this screen and takes its clicks already.
        // `AppModel.importConfiguration` refuses a locked app as well. This
        // guard keeps the third route, a keyboard activation, closed too.
        guard allowsActions else { return }
        do {
            guard let archive = try ConfigurationFileAccess.chooseImport() else { return }
            try appModel.importConfiguration(archive, applyPreferences: true, mode: .add)
            importMessage = "Imported \(archive.workspaces.count) workspaces and \(archive.services.count) services. Sign in to each imported service to use it."
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: NotificationAuthorizationPresentation.systemSettingsURLString
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Surface

    /// The card surface for the running system and the user's settings.
    ///
    /// It follows the rules of `FloatingNoticeCard`: Liquid Glass on macOS 26
    /// when the glass setting allows it, the material surface otherwise, and an
    /// opaque window background under Reduce Transparency.
    @ViewBuilder
    private var cardSurface: some View {
        if reduceTransparency {
            cardShape.fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *), appState.liquidGlassStyle != .off {
            glassCardSurface
        } else {
            materialCardSurface
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private var glassCardSurface: some View {
        let tint = PaguroColor.Fill.glassTint(intensity: appState.liquidGlassIntensity)
        switch appState.liquidGlassStyle {
        case .clear:
            Rectangle().fill(.clear).glassEffect(.clear.tint(tint), in: cardShape)
        case .off, .regular:
            Rectangle().fill(.clear).glassEffect(.regular.tint(tint), in: cardShape)
        }
    }

    private var materialCardSurface: some View {
        ZStack {
            cardShape.fill(.regularMaterial)
            cardShape.fill(
                PaguroColor.Fill.shellMaterialTint(
                    intensity: appState.liquidGlassIntensity
                )
            )
        }
    }

    /// A hairline lifts the card off the glass. Increase Contrast makes it a
    /// full border, because the hairline can disappear over a bright desktop.
    private var borderColor: Color {
        colorSchemeContrast == .increased ? PaguroColor.shellBorder : PaguroColor.hairline
    }

    private var borderWidth: CGFloat {
        colorSchemeContrast == .increased ? 1 : 0.5
    }
}
