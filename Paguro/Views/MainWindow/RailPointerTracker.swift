import AppKit
import SwiftUI

/// Reports every pointer move over the rail viewport.
///
/// SwiftUI hover does not reach this rail everywhere. A trace showed that
/// `onContinuousHover` sent no event for about 11 points above each icon: the
/// padding at the top of a row, just past the edge of the row before it. The
/// pointer crossed that band with no update, and the magnification then jumped
/// to catch up.
///
/// An AppKit tracking area sends every move inside its rectangle to its owner,
/// whatever view is under the pointer. The view takes no clicks, so the cells
/// keep their buttons, menus, and drags.
struct RailPointerTracker: NSViewRepresentable {
    let onPhase: (HoverPhase) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onPhase = onPhase
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onPhase = onPhase
    }

    final class TrackingView: NSView {
        var onPhase: (HoverPhase) -> Void = { _ in }

        // SwiftUI measures from the top edge.
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas where area.owner === self {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            report(event)
        }

        override func mouseMoved(with event: NSEvent) {
            report(event)
        }

        override func mouseExited(with event: NSEvent) {
            onPhase(.ended)
        }

        private func report(_ event: NSEvent) {
            onPhase(.active(convert(event.locationInWindow, from: nil)))
        }
    }
}
