import AppKit
import SwiftUI

/// Records input before AppKit gives the grid focus on mouse-down.
struct SetupInputMethodObserver: NSViewRepresentable {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }

    func updateNSView(_ view: InputView, context: Context) {
        view.isEnabled = isEnabled
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: InputView, coordinator: ()) {
        view.stopObserving()
    }

    final class InputView: NSView {
        var isEnabled = false
        var onChange: ((Bool) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
                [weak self] event in
                MainActor.assumeIsolated { self?.observe(event) }
                return event
            }
        }

        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        func observe(_ event: NSEvent) {
            guard isEnabled, let window, event.window === window else { return }
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                onChange?(false)
            case .keyDown:
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return }
                onChange?(true)
            default:
                break
            }
        }
    }
}
