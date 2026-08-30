import AppKit
import SwiftUI

/// AppKit support for the main window's backdrop, chrome, and drag handle.

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
/// The frost view obscures background detail. The glass view changes the
/// optical style. The tint gives the transparency control exact endpoints.
private final class WindowBackdropContainerView: NSView {
    private let frostView = NSVisualEffectView()
    private let tintView = WindowShellTintView()
    /// The Liquid Glass layer, present only on macOS 26 and later.
    ///
    /// `NSGlassEffectView` does not exist below macOS 26, so the property
    /// cannot name that type. Earlier systems leave it nil and show the frost
    /// and tint layers alone, which is the Off style.
    private var glassView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        frostView.frame = bounds
        frostView.autoresizingMask = [.width, .height]
        frostView.material = .underWindowBackground
        frostView.blendingMode = .behindWindow
        frostView.state = .followsWindowActiveState
        frostView.alphaValue = GlassLabDefaults.regularFrost
        addSubview(frostView)

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.frame = bounds
            glass.autoresizingMask = [.width, .height]
            glass.style = .clear
            glass.tintColor = nil
            glass.cornerRadius = 0
            addSubview(glass, positioned: .above, relativeTo: frostView)
            glassView = glass
        }

        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        addSubview(tintView, positioned: .above, relativeTo: glassView ?? frostView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        glassStyle: ShellGlassStyle,
        transparency: Double
    ) {
        frostView.alphaValue = glassStyle.frostOpacity

        if #available(macOS 26, *), let glass = glassView as? NSGlassEffectView {
            switch glassStyle {
            case .off:
                glass.isHidden = true
            case .clear:
                glass.isHidden = false
                glass.style = .clear
            case .regular:
                glass.isHidden = false
                glass.style = .regular
            }
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
/// was grabbed by the window move before the SwiftUI reorder could start — the
/// window slid instead of the tab reordering. A view nested in a SwiftUI
/// `ScrollView` can't opt out of that drag (the scroll view short-circuits
/// AppKit hit-testing, so a `mouseDownCanMoveWindow == false` nested view is
/// never consulted).
///
/// So we turn the OS window drag off for that layout and hand dragging to
/// explicit `WindowDragHandle`s instead (Chrome's model). The sidebar layout,
/// whose rail doesn't hold draggable tabs in the band, keeps the normal drag.
///
/// The Dock-style reorder in `RailServiceCell` uses a SwiftUI `DragGesture`
/// rather than a system drag. AppKit steals a mouse drag in the band before any
/// SwiftUI recognizer, so this rule still applies without a change. Keep
/// `isMovable` false for the bar layout.
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
            // The SwiftUI minimum width does not reach the window, which a
            // drag of its edge can then narrow until the shell overlaps its
            // own content. Only the width is held: a short window still
            // compresses, which the rail and the web content both accept.
            window.contentMinSize = NSSize(
                width: BlattaMetric.Window.minimumContentWidth,
                height: window.contentMinSize.height
            )

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
    /// `(26, 26)` and uses a 23 point gap between button centers. Blatta keeps its
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
        let centerY: CGFloat = BlattaMetric.Toolbar.height / 2
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
