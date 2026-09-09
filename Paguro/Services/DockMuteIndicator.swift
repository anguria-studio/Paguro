import AppKit

@MainActor
final class DockMuteIndicator {
    static let shared = DockMuteIndicator()
    private var isMuted = false

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        let tile = NSApplication.shared.dockTile
        tile.contentView = muted ? MutedDockIconView(frame: NSRect(origin: .zero, size: tile.size)) : nil
        tile.display()
    }
}

@MainActor
private final class MutedDockIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSApplication.shared.applicationIconImage?.draw(in: bounds)
        // Muting replaces the unread badge in the same corner.
        let diameter = bounds.width * 0.34
        let circle = NSRect(x: bounds.maxX - diameter, y: bounds.maxY - diameter,
                            width: diameter, height: diameter)
        NSColor(white: 0.16, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: circle).fill()
        let symbol = NSImage(systemSymbolName: "bell.slash.fill",
                             accessibilityDescription: "All services muted")?
            .withSymbolConfiguration(.init(paletteColors: [.white]))
        let inset = diameter * 0.2
        symbol?.draw(in: circle.insetBy(dx: inset, dy: inset))
    }
}
