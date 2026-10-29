#if !APP_STORE
import AppKit

/// Crop the page edge under one rounded host surface, without an extra frame.
@MainActor
final class BrowserExtensionPopupContentController: NSViewController {
    private static let edgeCrop: CGFloat = 2
    private static let cornerRadius: CGFloat = 14
    private static let controlsHeight: CGFloat = 32
    private let keepOpenButton = NSButton(checkboxWithTitle: "Keep open", target: nil, action: nil)
    private let pageSurface = BrowserExtensionPopupSurface()
    private let content: NSViewController
    private weak var popover: NSPopover?

    static func prepare(_ popover: NSPopover) {
        guard let content = popover.contentViewController,
              !(content is BrowserExtensionPopupContentController) else { return }
        let container = BrowserExtensionPopupContentController(content: content)
        container.popover = popover
        // WebKit resizes its scrolling surface separately from the native window.
        // Keep both sizes in step instead of animating through different heights.
        popover.animates = false
        popover.contentViewController = container
        popover.contentSize = container.preferredContentSize
    }

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        addChild(content)
        let size = content.preferredContentSize == .zero ? content.view.frame.size : content.preferredContentSize
        preferredContentSize = size
        view.setFrameSize(preferredContentSize)
    }

    required init?(coder: NSCoder) { nil }

    static func present(_ popover: NSPopover, relativeTo rect: NSRect, of anchor: NSView, preferredEdge: NSRectEdge,
                        mayPresent: () -> Bool = { true }) async throws {
        guard mayPresent(), anchor.window?.isVisible == true else { throw CancellationError() }
        // Activation can restore the main window. Finish that handoff before opening the popup.
        AppDelegate.prepareToShowWindow()
        for _ in 0..<100 {
            guard mayPresent() else { throw CancellationError() }
            if NSApp.isActive { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard mayPresent(), NSApp.isActive, anchor.window?.isVisible == true else {
            throw CocoaError(.userCancelled)
        }
        prepare(popover)
        (popover.contentViewController as? BrowserExtensionPopupContentController)?.setKeptOpen(false)
        popover.show(relativeTo: rect, of: anchor, preferredEdge: preferredEdge)
        guard let container = popover.contentViewController as? BrowserExtensionPopupContentController,
              let window = container.view.window else { throw CocoaError(.userCancelled) }
        window.makeKey()
        guard window.makeFirstResponder(container.content.view), window.isKeyWindow else {
            popover.close()
            throw CocoaError(.userCancelled)
        }
    }

    // WebKit updates the popover controller with the page size as its content changes.
    override var preferredContentSize: NSSize {
        get { super.preferredContentSize }
        set {
            let size = NSSize(width: max(160, newValue.width - Self.edgeCrop * 2),
                              height: max(1, newValue.height - Self.edgeCrop * 2) + Self.controlsHeight)
            super.preferredContentSize = size
            if let popover, popover.contentSize != size { popover.contentSize = size }
        }
    }

    private func setKeptOpen(_ keptOpen: Bool) {
        keepOpenButton.state = keptOpen ? .on : .off
        popover?.behavior = keptOpen ? .applicationDefined : .transient
    }

    @objc private func toggleKeepOpen(_ sender: NSButton) {
        setKeptOpen(sender.state == .on)
    }

    @objc private func dismissPopup(_ sender: NSButton) {
        popover?.performClose(sender)
    }

    override func loadView() {
        view = BrowserExtensionPopupSurface()
        view.wantsLayer = true
        view.clipsToBounds = true
        view.layer?.cornerRadius = Self.cornerRadius
        view.layer?.masksToBounds = true

        keepOpenButton.target = self
        keepOpenButton.action = #selector(toggleKeepOpen(_:))
        keepOpenButton.font = .systemFont(ofSize: 13)
        keepOpenButton.toolTip = "Keep this extension open while using the page."
        keepOpenButton.setAccessibilityIdentifier("extension.popup.keepOpen")
        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)!,
            target: self, action: #selector(dismissPopup(_:)))
        closeButton.isBordered = false
        closeButton.setAccessibilityLabel("Close extension")
        closeButton.setAccessibilityIdentifier("extension.popup.close")
        closeButton.toolTip = "Close extension (Esc)"
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.keyEquivalentModifierMask = []

        let controls = NSView()
        for child in [controls, pageSurface] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        for button in [keepOpenButton, closeButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            controls.addSubview(button)
        }
        pageSurface.wantsLayer = true
        pageSurface.layer?.masksToBounds = true
        content.view.translatesAutoresizingMaskIntoConstraints = false
        pageSurface.addSubview(content.view)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.topAnchor.constraint(equalTo: view.topAnchor),
            controls.heightAnchor.constraint(equalToConstant: Self.controlsHeight),
            keepOpenButton.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 10),
            keepOpenButton.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: keepOpenButton.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            pageSurface.topAnchor.constraint(equalTo: controls.bottomAnchor),
            pageSurface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageSurface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageSurface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.view.leadingAnchor.constraint(equalTo: pageSurface.leadingAnchor, constant: -Self.edgeCrop),
            content.view.trailingAnchor.constraint(equalTo: pageSurface.trailingAnchor, constant: Self.edgeCrop),
            content.view.topAnchor.constraint(equalTo: pageSurface.topAnchor, constant: -Self.edgeCrop),
            content.view.bottomAnchor.constraint(equalTo: pageSurface.bottomAnchor, constant: Self.edgeCrop)
        ])
    }
}

private final class BrowserExtensionPopupSurface: NSView {
    // Match the web view's top origin when its content grows or scrolls.
    override var isFlipped: Bool { true }
}
#endif
