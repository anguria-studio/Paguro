import AppKit
import SwiftUI

/// Window-drag plumbing and the reorder maths the rail depends on.
///
/// All of it moved here verbatim when `ServiceSidebarView` and `SpaceStripView`
/// were replaced by `UnifiedRailView` (build step 5 of concept C). It is the
/// part the UX audit rated severity 0 — tested, and working — so it was moved
/// rather than rewritten, and it lives in its own file so the next rail rebuild
/// cannot take it down with the view it happened to sit in.

enum ServiceReorderPlacement {
    case before
    case after
}

/// Wraps a SwiftUI hosting view in the main-window appearance experiment.
///
/// The order is backdrop frost, optional Liquid Glass, protective tint, then
/// SwiftUI content. `WKWebView` stays opaque in the top content layer.
@MainActor
private enum WindowBackdropInstaller {
    static func install(
        in window: NSWindow,
        glassStyle: ShellGlassStyle,
        transparency: Double
    ) {
        window.isOpaque = false
        window.backgroundColor = .clear

        if let container = window.contentView as? WindowBackdropContainerView {
            container.update(
                glassStyle: glassStyle,
                transparency: transparency
            )
            return
        }

        guard let hostedContent = window.contentView else { return }
        let container = WindowBackdropContainerView(frame: hostedContent.frame)

        // Keep the hosting view alive while assigning the new AppKit content
        // view. AppKit detaches the old content view during this assignment.
        window.contentView = container
        container.install(hostedContent: hostedContent)
        container.update(
            glassStyle: glassStyle,
            transparency: transparency
        )
    }
}

/// The native full-window layers that the Glass Lab controls.
///
/// The fixed frost view obscures background detail. The glass view changes the
/// optical style. The tint gives the transparency control exact endpoints.
private final class WindowBackdropContainerView: NSView {
    private let frostView = NSVisualEffectView()
    private let glassView = NSGlassEffectView()
    private let tintView = WindowShellTintView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        frostView.frame = bounds
        frostView.autoresizingMask = [.width, .height]
        frostView.material = .underWindowBackground
        frostView.blendingMode = .behindWindow
        frostView.state = .followsWindowActiveState
        frostView.alphaValue = CGFloat(GlassLabDefaults.fixedFrost)
        addSubview(frostView)

        glassView.frame = bounds
        glassView.autoresizingMask = [.width, .height]
        glassView.style = .clear
        glassView.tintColor = nil
        glassView.cornerRadius = 0
        addSubview(glassView, positioned: .above, relativeTo: frostView)

        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        addSubview(tintView, positioned: .above, relativeTo: glassView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        glassStyle: ShellGlassStyle,
        transparency: Double
    ) {
        switch glassStyle {
        case .off:
            glassView.isHidden = true
        case .clear:
            glassView.isHidden = false
            glassView.style = .clear
        case .regular:
            glassView.isHidden = false
            glassView.style = .regular
        }

        tintView.transparency = GlassIntensityScale.normalized(transparency)
    }

    func install(hostedContent: NSView) {
        hostedContent.frame = bounds
        hostedContent.autoresizingMask = [.width, .height]
        hostedContent.wantsLayer = true
        hostedContent.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(hostedContent, positioned: .above, relativeTo: tintView)
    }
}

/// Draws a fixed RGB tint whose opacity is the user-controlled value.
///
/// Use a layer background so a live slider change redraws this AppKit view.
/// The explicit layer also keeps the 0 percent endpoint opaque.
private final class WindowShellTintView: NSView {
    var transparency = GlassLabDefaults.transparency {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let opacity = GlassIntensityScale.shellOpacity(transparency)
        let color = if isDark {
            NSColor(
                srgbRed: CGFloat(36) / 255,
                green: CGFloat(33) / 255,
                blue: CGFloat(37) / 255,
                alpha: opacity
            )
        } else {
            NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: opacity)
        }
        layer?.backgroundColor = color.cgColor
    }
}

/// Applies the native title-bar geometry and sets background window dragging.
///
/// With `.windowStyle(.hiddenTitleBar)` the top ~32px stays a title-bar drag
/// band. In the bar layout the rail sits in that band, so a click-drag on a tab
/// was grabbed by the window move before SwiftUI's `.draggable` reorder could
/// start — the window slid instead of the tab reordering. A view nested in a
/// SwiftUI `ScrollView` can't opt out of that drag (the scroll view
/// short-circuits AppKit hit-testing, so a `mouseDownCanMoveWindow == false`
/// nested view is never consulted).
///
/// So we turn the OS window drag off for that layout and hand dragging to
/// explicit `WindowDragHandle`s instead (Chrome's model). The sidebar layout,
/// whose rail doesn't hold draggable tabs in the band, keeps the normal drag.
struct WindowChromeConfigurator: NSViewRepresentable {
    let isMovable: Bool
    let glassStyle: ShellGlassStyle
    let glassIntensity: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyWhenAttached(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyWhenAttached(to: nsView, coordinator: context.coordinator)
    }

    private func applyWhenAttached(to view: NSView, coordinator: Coordinator) {
        let isMovable = isMovable
        let glassStyle = glassStyle
        let glassIntensity = glassIntensity
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.configure(
                window: window,
                isMovable: isMovable,
                glassStyle: glassStyle,
                glassIntensity: glassIntensity
            )
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observerTokens: [NSObjectProtocol] = []

        deinit {
            removeObservers()
        }

        @MainActor
        func configure(
            window: NSWindow,
            isMovable: Bool,
            glassStyle: ShellGlassStyle,
            glassIntensity: Double
        ) {
            window.isMovable = isMovable
            WindowBackdropInstaller.install(
                in: window,
                glassStyle: glassStyle,
                transparency: glassIntensity
            )
            WindowChromeConfigurator.applyReferenceTrafficLightGeometry(to: window)

            guard self.window !== window else { return }
            removeObservers()
            self.window = window

            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            observerTokens = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak window] _ in
                    // AppKit can reset the standard button frames after it
                    // finishes a zoom or a full-screen transition.
                    DispatchQueue.main.async {
                        guard let window else { return }
                        WindowChromeConfigurator.applyReferenceTrafficLightGeometry(to: window)
                    }
                }
            }
        }

        private func removeObservers() {
            for token in observerTokens {
                NotificationCenter.default.removeObserver(token)
            }
            observerTokens.removeAll()
        }
    }

    /// A stock unified toolbar puts the center of the first traffic light at
    /// `(26, 26)` and uses a 23 point gap between button centers. Atoll keeps its
    /// controls in the service-aware SwiftUI header, so it applies the same
    /// public AppKit button frames without adding a second toolbar surface.
    private static func applyReferenceTrafficLightGeometry(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        let buttonTypes: [NSWindow.ButtonType] = [
            .closeButton,
            .miniaturizeButton,
            .zoomButton,
        ]
        let firstCenterX: CGFloat = 26
        let centerY: CGFloat = AtollMetric.Toolbar.height / 2
        let centerGap: CGFloat = 23

        for (index, buttonType) in buttonTypes.enumerated() {
            guard let button = window.standardWindowButton(buttonType),
                  let container = button.superview
            else { continue }

            let origin = NSPoint(
                x: firstCenterX + (CGFloat(index) * centerGap) - (button.frame.width / 2),
                y: container.bounds.height - centerY - (button.frame.height / 2)
            )
            button.setFrameOrigin(origin)
        }
    }
}

/// A transparent strip that moves the window on click-drag, the way Chrome lets
/// you drag the empty part of its tab strip. Used to fill the reserved gap in
/// the top bar, where the OS window drag is off (see
/// `WindowChromeConfigurator`). A double-click zooms, matching a title bar.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.performZoom(nil)
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

enum SpaceMove {
    /// The spaces a service can be moved into: every space except the ones it
    /// already belongs to. Moving into a space it's already in would just
    /// double-link it, and the current space is one of those memberships, so
    /// this naturally leaves it out too. Order follows `allSpaceIDs` (the
    /// sorted space list).
    static func eligibleSpaceIDs(allSpaceIDs: [UUID], memberSpaceIDs: Set<UUID>) -> [UUID] {
        allSpaceIDs.filter { !memberSpaceIDs.contains($0) }
    }
}

enum ServiceReorder {
    static func reorderedIDs(
        _ ids: [UUID],
        moving droppedID: UUID,
        relativeTo targetID: UUID,
        placement: ServiceReorderPlacement
    ) -> [UUID]? {
        guard droppedID != targetID,
              let fromIndex = ids.firstIndex(of: droppedID),
              let targetIndex = ids.firstIndex(of: targetID) else {
            return nil
        }

        var reordered = ids
        let moved = reordered.remove(at: fromIndex)

        var toIndex = targetIndex
        if placement == .after {
            toIndex += 1
        }
        if fromIndex < toIndex {
            toIndex -= 1
        }
        guard fromIndex != toIndex else {
            return nil
        }

        reordered.insert(moved, at: toIndex)
        return reordered
    }
}
