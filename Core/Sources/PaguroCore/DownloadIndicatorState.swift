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

/// What one download row says about the service that started the download.
///
/// The download list is global, so every row has to name its own source. The
/// record carries the service name that applied when the download began, so the
/// row stays readable after a rename or a deletion.
///
/// The three cases differ in what the row can draw. A live service has a saved
/// icon, so the row draws it. A service that no longer exists has none, so the
/// row keeps the recorded name with a generic mark. A download that Paguro
/// could not attribute has no source at all, and its row shows none: an invented
/// source would be worse than no source.
public enum DownloadSource: Equatable, Sendable {
    /// Paguro could not name the service. The row shows no source.
    case unattributed
    /// The service still exists. The row draws its saved icon beside the name.
    case service(label: String)
    /// The service is gone. The row keeps the recorded name with a generic mark.
    case removedService(label: String)

    /// Returns the source for one download record.
    ///
    /// - Parameters:
    ///   - serviceID: The service on the record, or nil for a download that
    ///     Paguro could not attribute.
    ///   - label: The service name that the record captured when the download
    ///     began.
    ///   - serviceExists: Whether that service is still in the workspace.
    public static func resolve(
        serviceID: UUID?,
        label: String?,
        serviceExists: Bool
    ) -> DownloadSource {
        guard serviceID != nil else { return .unattributed }
        let name = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A record with a service but no usable name can say nothing useful,
        // so it reads as a download without a source instead of as a blank row.
        guard !name.isEmpty else { return .unattributed }
        return serviceExists ? .service(label: name) : .removedService(label: name)
    }

    /// The name to print under the file name, or nil for no source line.
    public var label: String? {
        switch self {
        case .unattributed: return nil
        case let .service(label), let .removedService(label): return label
        }
    }

    /// Whether the row draws the saved icon of the service.
    ///
    /// A removed service has no icon left, so its row draws a generic mark.
    public var drawsServiceIcon: Bool {
        if case .service = self { return true }
        return false
    }

    /// The part of the row's spoken label that names the source, or nil.
    ///
    /// The row reads as "report.pdf, from Gmail, downloading", so the source
    /// arrives between the file name and the state.
    public var spokenPhrase: String? {
        guard let label else { return nil }
        return "from \(label)"
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

    // MARK: - The mark that reports a start

    /// Where the flying mark starts, as a part of the web content height.
    ///
    /// The mark keeps the x position of the header control, so it travels
    /// straight up. A little above the middle of the page reads as a start
    /// place, not as a notice that covers the content.
    public static let flightStartFraction: Double = 0.42

    /// The fade and growth of the mark at its start place.
    public static let flightEntry: Duration = .milliseconds(120)

    /// The scale the mark grows from at its start place.
    public static let flightEntryScale: Double = 0.72

    /// The travel from the start place up to the control.
    public static let flightTravel: Duration = .milliseconds(440)

    /// The fade at the end of the travel.
    ///
    /// It runs inside the last part of the travel, so the mark stays readable
    /// for most of the way and gives its place to the control at the end.
    public static let flightExit: Duration = .milliseconds(240)

    /// The scale the mark shrinks to as it reaches the control.
    public static let flightArrivalScale: Double = 0.55

    /// The complete length of one flight, from the first frame to the landing.
    ///
    /// The value is longer than `DownloadIndicatorState.ringDelay` on purpose.
    /// The first download of a service has no control in the header yet,
    /// because the indicator earns its place after that delay. A landing after
    /// it therefore meets a control that has already entered, so the entry and
    /// the landing read as one handoff.
    public static var flightTotal: Duration { flightEntry + flightTravel }

    /// The fade at the control that replaces the travel for Reduce Motion.
    public static let flightFade: Duration = .milliseconds(200)

    /// How long a mark waits for a control that is not in the header yet.
    ///
    /// A download that the user stops inside the ring delay never gives the
    /// control a place, so a mark that waits needs an end of its own.
    public static let flightDestinationWait: Duration = .milliseconds(1500)
}

/// How Paguro reports a download start.
///
/// Reduce Motion removes the travel. The cue then happens at the control only,
/// so the user still sees that a download began and nothing crosses the page.
public enum DownloadStartCue: Equatable, Sendable {
    /// A mark rises from the web content into the header control.
    case flight
    /// A short fade at the control, with no travel.
    case destinationFade

    public static func resolve(reduceMotion: Bool) -> DownloadStartCue {
        reduceMotion ? .destinationFade : .flight
    }

    /// The cue for one download start, with one global download control.
    ///
    /// The control counts the downloads of every service, so a start in a
    /// service that the window does not show must still reach the header. A
    /// mark cannot travel from that start, because the page it belongs to is
    /// not on screen: a mark out of the visible page would name the wrong
    /// source. The destination cue answers this case, the same cue that Reduce
    /// Motion uses.
    ///
    /// `contentIsOnScreen` is false when the window shows no service page. The
    /// mark then has no place to leave from, so the start produces no cue at
    /// all. A start while the window is closed reaches this rule from no
    /// caller, because the overlay that draws the marks lives with the window.
    ///
    /// A download without a service belongs to every service, so it keeps the
    /// travel.
    ///
    /// - Returns: The cue, or nil when the start produces none.
    public static func resolve(
        eventServiceID: UUID?,
        selectedServiceID: UUID?,
        reduceMotion: Bool,
        contentIsOnScreen: Bool
    ) -> DownloadStartCue? {
        guard contentIsOnScreen else { return nil }
        guard !reduceMotion else { return .destinationFade }
        let isOnScreen = eventServiceID == nil || eventServiceID == selectedServiceID
        return isOnScreen ? .flight : .destinationFade
    }

    /// How long the cue lasts.
    public var duration: Duration {
        switch self {
        case .flight: return DownloadIndicatorMotion.flightTotal
        case .destinationFade: return DownloadIndicatorMotion.flightFade
        }
    }

    /// Whether the cue moves a mark across the window.
    public var hasTravel: Bool { self == .flight }
}

/// Decides how many flying marks a group of download starts produces.
///
/// One mark for each start would read as noise: ten files at one time would
/// send ten marks up the same line. The rule therefore groups the starts that
/// share a moment, keeps two marks apart when they do not, and stops adding
/// marks at a limit. The header badge still counts every download, so the
/// limit hides no download.
///
/// The planner reads no clock. The caller gives the start time, the way
/// `DownloadIndicatorState` receives its elapsed value. The caller also reports
/// the end of each flight with `forget(flightID:)`, because only the view knows
/// when a mark reached the control. `staleLife` removes a flight that no caller
/// ever reported, so one lost report cannot stop every later mark.
public struct DownloadFlightPlanner: Equatable, Sendable {

    /// Starts inside this time of a flight join that flight.
    public static let coalesceWindow: Duration = .milliseconds(300)

    /// The shortest gap between the launch of two marks.
    ///
    /// It is longer than `coalesceWindow`, so a start that misses the group of
    /// one mark still waits until that mark is clear of its start place.
    public static let minimumGap: Duration = .milliseconds(400)

    /// How many marks can be on the way at one time.
    public static let maximumFlights = 3

    /// How long the planner keeps a flight that the caller never reported.
    public static let staleLife: Duration = .seconds(2)

    /// What one download start produces.
    public enum Outcome: Equatable, Sendable {
        /// A new mark leaves after this delay.
        case launch(flightID: Int, delay: Duration)
        /// The start joins a mark that is already on the way, so no new mark
        /// appears. The header count reports the download.
        case joinsFlight(flightID: Int)
        /// Too many marks are already on the way. The header count reports the
        /// download.
        case capped
    }

    /// One mark that the planner has promised.
    private struct Flight: Equatable, Sendable {
        let id: Int
        /// When the mark leaves its start place.
        let launchAt: Date
        /// How many starts this mark reports.
        var count: Int
    }

    private var flights: [Flight] = []
    private var lastFlightID = 0

    public init() {}

    /// The marks that the planner still counts.
    public var flightCount: Int { flights.count }

    /// How many starts one mark reports, or nil for a mark the planner dropped.
    public func count(ofFlight id: Int) -> Int? {
        flights.first { $0.id == id }?.count
    }

    /// Answers one download start.
    public mutating func plan(startedAt: Date) -> Outcome {
        dropStaleFlights(before: startedAt)

        if let index = newestFlightIndex,
           startedAt.timeIntervalSince(flights[index].launchAt)
               < Self.coalesceWindow.timeIntervalValue {
            flights[index].count += 1
            return .joinsFlight(flightID: flights[index].id)
        }

        guard flights.count < Self.maximumFlights else { return .capped }

        let earliestLaunch = newestFlightIndex.map {
            flights[$0].launchAt.addingTimeInterval(Self.minimumGap.timeIntervalValue)
        }
        let launchAt = max(startedAt, earliestLaunch ?? startedAt)
        lastFlightID += 1
        flights.append(Flight(id: lastFlightID, launchAt: launchAt, count: 1))
        return .launch(flightID: lastFlightID, delay: Self.delay(from: startedAt, to: launchAt))
    }

    /// The wait before a mark leaves, in whole milliseconds.
    ///
    /// A date difference carries floating-point noise. An animation delay needs
    /// no more resolution than a millisecond, so the rounding keeps the result
    /// exact for a reader and for a test.
    private static func delay(from startedAt: Date, to launchAt: Date) -> Duration {
        let milliseconds = max(0, launchAt.timeIntervalSince(startedAt)) * 1000
        return .milliseconds(Int(milliseconds.rounded()))
    }

    /// Removes one mark, because it reached the control or ended another way.
    public mutating func forget(flightID: Int) {
        flights.removeAll { $0.id == flightID }
    }

    /// Removes every mark. `AppState.shutdown()` reaches this through the app
    /// state that owns the planner.
    public mutating func forgetAll() {
        flights.removeAll()
    }

    /// The newest promised mark, which is the only one a start can join.
    private var newestFlightIndex: Int? {
        guard !flights.isEmpty else { return nil }
        return flights.indices.max { flights[$0].launchAt < flights[$1].launchAt }
    }

    private mutating func dropStaleFlights(before now: Date) {
        flights.removeAll {
            now.timeIntervalSince($0.launchAt) >= Self.staleLife.timeIntervalValue
        }
    }
}

extension Duration {
    /// The value in seconds, for arithmetic with `Date`.
    ///
    /// The type stays inside this package, so the app target keeps its own
    /// conversion for the SwiftUI animation API.
    var timeIntervalValue: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
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

    /// The VoiceOver announcement for a download that has just started.
    ///
    /// The flying mark carries no accessibility element, and the control keeps
    /// its own label, so this announcement is the only spoken report of a
    /// start. The app posts one announcement for each mark, so a group of
    /// starts does not talk over itself.
    public static func startAnnouncement(filename: String) -> String {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Download started" : "Download started: \(name)"
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
