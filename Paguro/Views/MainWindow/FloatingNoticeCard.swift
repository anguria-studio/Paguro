import PaguroCore
import SwiftUI

/// One transient, service-scoped notice.
///
/// The card shape suits a notice that reports a fact about the service the user
/// is looking at and then leaves. An app-level state that needs action, or that
/// stays until something changes, keeps the full-width `NoticeStrip`.
struct FloatingNotice: Identifiable {
    enum ID: Hashable {
        /// The pool released a background service to stay inside its limit.
        case capacityEviction
        /// The web view cannot use a passkey for sign-in.
        case passkeyUnavailable
    }

    let id: ID
    let systemImage: String
    let title: String
    let message: String
    /// Removes the notice. The owner of the state does the removal, so the card
    /// stays free of the rule that produced it.
    let dismiss: () -> Void
}

/// A notification-style card above the web content.
///
/// It copies the shape of a macOS notification banner: a tinted symbol tile, a
/// short title, a secondary explanation, and a close button that stays quiet
/// until the pointer arrives. The web page below keeps its keyboard focus and
/// its clicks, because the card takes no focus and covers only its own frame.
struct FloatingNoticeCard: View {
    let notice: FloatingNotice

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var closeButtonIsHovering = false

    /// The longest explanation the card shows. A longer text is cut, so one
    /// notice cannot grow into a page-sized panel.
    private static let messageLineLimit = 4
    private static let symbolTileSize: CGFloat = 26

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaguroRadius.surface, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            symbolTile

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: PaguroTypeSize.body, weight: .semibold))
                    .foregroundStyle(PaguroColor.Text.primary)

                Text(notice.message)
                    .font(.system(size: PaguroTypeSize.body))
                    .foregroundStyle(PaguroColor.Text.secondary)
                    .lineLimit(Self.messageLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver reads the title and the explanation as one notice. The
            // close button stays a separate element, so it keeps its own label
            // and its own action.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(notice.title). \(notice.message)")

            closeButton
        }
        .padding(12)
        .background { surface }
        .overlay { shape.strokeBorder(borderColor, lineWidth: borderWidth) }
        .clipShape(shape)
        .shadow(color: shadowColor, radius: 12, y: 4)
        .onAppear {
            // The card carries no sound and takes no focus, so VoiceOver needs
            // the announcement to report it.
            AccessibilityNotification.Announcement("\(notice.title). \(notice.message)").post()
        }
    }

    private var symbolTile: some View {
        RoundedRectangle(cornerRadius: PaguroRadius.icon, style: .continuous)
            .fill(Color.accentColor.opacity(0.16))
            .frame(width: Self.symbolTileSize, height: Self.symbolTileSize)
            .overlay {
                Image(systemName: notice.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button(action: notice.dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PaguroColor.Text.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A macOS notification keeps its close control quiet until the pointer
        // arrives. It stays visible, because a control that disappears also
        // disappears for keyboard focus.
        .opacity(closeButtonIsHovering ? 1 : 0.5)
        .onHover { closeButtonIsHovering = $0 }
        .help("Dismiss")
        .accessibilityLabel("Dismiss notice")
    }

    /// The card surface for the running system and the user's settings.
    ///
    /// Reduce Transparency wins over every glass form, because the card sits
    /// above a web page that Paguro does not control.
    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *), appState.liquidGlassStyle != .off {
            glassSurface
        } else {
            materialSurface
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private var glassSurface: some View {
        let tint = PaguroColor.Fill.glassTint(intensity: appState.liquidGlassIntensity)
        switch appState.liquidGlassStyle {
        case .clear:
            Rectangle().fill(.clear).glassEffect(.clear.tint(tint), in: shape)
        case .off, .regular:
            Rectangle().fill(.clear).glassEffect(.regular.tint(tint), in: shape)
        }
    }

    private var materialSurface: some View {
        ZStack {
            shape.fill(.regularMaterial)
            shape.fill(
                PaguroColor.Fill.shellMaterialTint(intensity: appState.liquidGlassIntensity)
            )
        }
    }

    /// A hairline separates the card from a bright page. Increase Contrast
    /// makes it a full border, because the shadow alone can disappear over a
    /// busy page.
    private var borderColor: Color {
        colorSchemeContrast == .increased ? PaguroColor.shellBorder : PaguroColor.hairline
    }

    private var borderWidth: CGFloat {
        colorSchemeContrast == .increased ? 1 : 0.5
    }

    private var shadowColor: Color {
        .black.opacity(colorScheme == .dark ? 0.44 : 0.18)
    }
}

/// The top-trailing host for the floating notice cards.
///
/// It owns the order of the cards and their movement. The newest card takes the
/// top place, like a macOS notification, and the older cards move down.
struct FloatingNoticeStack: View {
    let notices: [FloatingNotice]
    /// The width of the web content below, which the card must not exceed.
    let availableWidth: CGFloat
    let findBarIsVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var order: [FloatingNotice.ID] = []

    private var cardWidth: CGFloat {
        CGFloat(FloatingNoticeLayout.width(availableWidth: Double(availableWidth)))
    }

    private var topInset: CGFloat {
        CGFloat(FloatingNoticeLayout.topInset(findBarIsVisible: findBarIsVisible))
    }

    /// The visible cards, newest first.
    private var orderedNotices: [FloatingNotice] {
        order.compactMap { id in notices.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: CGFloat(FloatingNoticeLayout.cardSpacing)) {
            ForEach(orderedNotices) { notice in
                FloatingNoticeCard(notice: notice)
                    .frame(width: cardWidth)
                    .transition(transition)
            }
        }
        .padding(.top, topInset)
        .padding(.horizontal, CGFloat(FloatingNoticeLayout.edgeInset))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(motion, value: order)
        .animation(motion, value: findBarIsVisible)
        .onAppear { updateOrder() }
        .onChange(of: notices.map(\.id)) { updateOrder() }
    }

    /// Puts a new notice at the top and drops the notices that are gone.
    private func updateOrder() {
        let current = notices.map(\.id)
        let kept = order.filter(current.contains)
        let added = current.filter { !kept.contains($0) }
        order = added.reversed() + kept
    }

    private var transition: AnyTransition {
        // Reduce Motion removes the travel and keeps the change readable.
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.28)
    }
}
