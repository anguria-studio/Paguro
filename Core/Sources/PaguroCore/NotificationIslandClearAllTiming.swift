/// Bounds the exit animation even when the island holds a long history.
public enum NotificationIslandClearAllTiming {
    public static func firstVisibleIndex(scrollOffset: Double, eventCount: Int) -> Int {
        guard scrollOffset.isFinite, scrollOffset > 0, eventCount > 0 else { return 0 }
        let pitch = NotificationIslandLayout.rowHeight + NotificationIslandLayout.rowSpacing
        let row = (scrollOffset / pitch).rounded(.down)
        if row >= Double(eventCount - 1) { return eventCount - 1 }
        return Int(row)
    }

    public static func cardDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.16 : 0.22
    }

    public static func delay(for index: Int, eventCount: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion, eventCount > 1 else { return 0 }
        // Only a few cards are visible above and inside the fold.
        return Double(min(max(0, index), min(eventCount - 1, 4))) * 0.045
    }

    public static func completionDelay(eventCount: Int, reduceMotion: Bool) -> Duration {
        guard eventCount > 0 else { return .zero }
        return .seconds(
            delay(for: eventCount - 1, eventCount: eventCount, reduceMotion: reduceMotion)
                + cardDuration(reduceMotion: reduceMotion)
        )
    }
}
