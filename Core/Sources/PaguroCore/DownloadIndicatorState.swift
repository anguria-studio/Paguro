import Foundation

/// The byte totals of the downloads that are still running.
///
/// The app adds the totals of every active download, so one indicator can show
/// the combined progress of a group.
public struct DownloadProgressTotals: Equatable, Sendable {
    public var activeCount: Int
    public var receivedBytes: Int64
    /// The expected size. A value of zero or less means that the server did not
    /// give a size.
    public var expectedBytes: Int64

    public init(
        activeCount: Int = 0,
        receivedBytes: Int64 = 0,
        expectedBytes: Int64 = 0
    ) {
        self.activeCount = activeCount
        self.receivedBytes = receivedBytes
        self.expectedBytes = expectedBytes
    }

    /// No download is active.
    public static let none = DownloadProgressTotals()

    /// The completed part of the active downloads, from zero to one.
    ///
    /// The value is nil when no active download reports an expected size. The
    /// indicator then shows a ring without a value.
    public var fraction: Double? {
        guard activeCount > 0, expectedBytes > 0 else { return nil }
        let value = Double(receivedBytes) / Double(expectedBytes)
        return min(1, max(0, value))
    }
}

/// Formats the compact count on the download control.
///
/// The rule follows `NotificationIslandCounterLabel`. The cap is smaller,
/// because this badge sits on a 28 point header control instead of the wide
/// island surface, and a three-character label would unbalance it.
public enum DownloadCountLabel {
    public static let maximumDisplayedCount = 9

    public static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > maximumDisplayedCount {
            return "\(maximumDisplayedCount)+"
        }
        return "\(count)"
    }
}

/// The motion values for the download control.
///
/// The rules keep these numbers so the view has no private timings and a
/// reader can find every one of them in one place. Reduce Motion replaces all
/// of them with an opacity change.
public enum DownloadIndicatorMotion {
    /// The scale the control grows from when it becomes visible.
    public static let entryScale: Double = 0.85
    /// The settling time of the entry spring.
    public static let entryDuration: Duration = .milliseconds(260)
    /// One complete turn of the arc that reports an unknown size.
    public static let indeterminateTurn: Duration = .milliseconds(900)
    /// The part of the ring that the unknown-size arc covers.
    public static let indeterminateArcFraction: Double = 0.3
    /// The peak of the single pulse after a download completes.
    public static let completionPulseScale: Double = 1.12
    /// The length of that pulse, including its return.
    public static let completionPulse: Duration = .milliseconds(300)
}

/// What the content header shows for the downloads of one service.
///
/// The state is a pure function of the download records. It does not read a
/// clock, and no result expires on its own. The user removes a record from the
/// download list, so the answer to "where did that file go?" stays available.
///
/// The caller supplies the elapsed time of its longest running download, so
/// this package still reads no clock.
public enum DownloadIndicatorState: Equatable, Sendable {
    /// The service has no download record, or its only download is too young
    /// to show.
    case hidden
    /// A download has run for longer than `ringDelay`. The fraction is nil for
    /// an unknown size.
    case active(fraction: Double?, count: Int, unseen: Int)
    /// No download shows a ring, and no record failed.
    case resting(count: Int, unseen: Int)
    /// No download shows a ring, and at least one record failed.
    case failed(count: Int, failedCount: Int, unseen: Int)

    /// How long a download must run before the control shows a ring.
    ///
    /// Most downloads finish sooner than this. A ring for such a download
    /// would appear and disappear inside one or two frames, which reads as a
    /// flicker rather than as progress.
    public static let ringDelay: Duration = .milliseconds(500)

    /// How long a completed download stays news.
    ///
    /// The badge reports arrivals, not a list the user must empty. A record
    /// stops counting after this time, or as soon as the user opens the list.
    /// The control itself stays, because it is the route back to the file.
    public static let badgeWindow: Duration = .seconds(12)

    /// Returns the indicator state for one service.
    ///
    /// `recordCount` is every row the list will show. It decides whether the
    /// control appears at all. `unseenCount` is the running downloads plus the
    /// completions the user has not seen, and it decides the badge. The two
    /// differ because a record outlives its own news.
    ///
    /// `longestActiveElapsed` is the running time of the oldest active
    /// download. A nil value means that the caller has no such download, or
    /// cannot measure one yet. Both cases count as "younger than the delay",
    /// so the control never shows a ring it cannot justify.
    ///
    /// A young download does not replace an existing result. It shows the
    /// ended state instead, so the control does not flash a ring over a mark
    /// the user is already reading. A young download with no result at all
    /// shows nothing: it has not earned a place in the header yet.
    public static func resolve(
        totals: DownloadProgressTotals,
        recordCount: Int,
        unseenCount: Int,
        failedCount: Int,
        longestActiveElapsed: Duration?
    ) -> DownloadIndicatorState {
        guard recordCount > 0 else { return .hidden }

        let hasActive = totals.activeCount > 0
        let ringEarned = (longestActiveElapsed ?? .zero) >= ringDelay

        if hasActive, ringEarned {
            return .active(
                fraction: totals.fraction,
                count: recordCount,
                unseen: unseenCount
            )
        }

        if hasActive {
            let endedCount = recordCount - totals.activeCount
            guard endedCount > 0 else { return .hidden }
        }

        return endedState(
            recordCount: recordCount,
            unseenCount: unseenCount,
            failedCount: failedCount
        )
    }

    /// The mark for a service whose downloads all show a result.
    private static func endedState(
        recordCount: Int,
        unseenCount: Int,
        failedCount: Int
    ) -> DownloadIndicatorState {
        if failedCount > 0 {
            return .failed(
                count: recordCount,
                failedCount: failedCount,
                unseen: unseenCount
            )
        }
        return .resting(count: recordCount, unseen: unseenCount)
    }

    /// The number of rows that the download list will show.
    public var recordCount: Int {
        switch self {
        case .hidden: return 0
        case let .active(_, count, _): return count
        case let .resting(count, _): return count
        case let .failed(count, _, _): return count
        }
    }

    /// The running downloads plus the completions the user has not seen.
    public var unseenCount: Int {
        switch self {
        case .hidden: return 0
        case let .active(_, _, unseen): return unseen
        case let .resting(_, unseen): return unseen
        case let .failed(_, _, unseen): return unseen
        }
    }

    /// The badge on the control, or nil when it shows none.
    ///
    /// The control stays in the header once the badge clears. The badge is
    /// transient feedback; the control is a route back to a file.
    public var badgeText: String? {
        DownloadCountLabel.text(for: unseenCount)
    }

    /// Whether the header draws the control.
    public var isVisible: Bool { self != .hidden }

    /// The part of the progress ring to draw, or nil for no ring value.
    public var ringFraction: Double? {
        if case let .active(fraction, _, _) = self { return fraction }
        return nil
    }

    /// Whether the control draws a progress ring.
    public var showsRing: Bool {
        if case .active = self { return true }
        return false
    }

    /// The mark that the control draws.
    ///
    /// The rules name the meaning of the mark. The view owns the artwork, so
    /// this package needs no knowledge of an asset catalog.
    public enum Glyph: Equatable, Sendable {
        /// Paguro's own download mark. The app supplies the drawing.
        case downloadMark
        /// A system symbol, named by its SF Symbol identifier.
        case systemSymbol(name: String)
    }

    /// The mark for the current state.
    ///
    /// A failed record keeps a separate mark, so a failure never looks the same
    /// as a group of successful downloads. Color alone would not carry that
    /// difference for every reader.
    public var glyph: Glyph {
        switch self {
        case .hidden, .active, .resting: return .downloadMark
        case .failed: return .systemSymbol(name: "exclamationmark.circle")
        }
    }

    /// The VoiceOver label for the control.
    ///
    /// A running download reports its completed percentage. A resting control
    /// reports how many records the list holds.
    public var accessibilityLabel: String {
        switch self {
        case .hidden:
            return Self.countText(0)
        case let .active(fraction, count, _):
            guard let fraction else { return "\(Self.countText(count)), downloading" }
            return "\(Self.countText(count)), \(Self.percentText(fraction)) percent complete"
        case let .resting(count, _):
            return Self.countText(count)
        case let .failed(count, failedCount, _):
            return "\(Self.countText(count)), \(failedCount) failed"
        }
    }

    /// The tooltip for the control.
    public var helpText: String {
        switch self {
        case .hidden:
            return "Downloads"
        case let .active(_, count, _):
            return "\(Self.countText(count)), downloading"
        case let .resting(count, _):
            return Self.countText(count)
        case let .failed(count, failedCount, _):
            return "\(Self.countText(count)), \(failedCount) failed"
        }
    }

    /// Readable text for a number of download records.
    public static func countText(_ count: Int) -> String {
        switch max(0, count) {
        case 0: return "No downloads"
        case 1: return "1 download"
        case let count: return "\(count) downloads"
        }
    }

    /// The whole percentage for a fraction, clamped to the valid range.
    public static func percentText(_ fraction: Double) -> String {
        let clamped = min(1, max(0, fraction))
        return String(Int((clamped * 100).rounded()))
    }
}
