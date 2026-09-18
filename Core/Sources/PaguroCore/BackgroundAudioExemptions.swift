import Foundation

/// Which background services keep their audio, and for how long.
///
/// A service that plays audible media at the moment it leaves the screen keeps
/// playing. Playback that starts while the service is already in the background
/// earns nothing, so a page cannot keep itself awake by autoplay. The web-view
/// pool owns the WebKit calls and the poll timer. This value owns the life
/// cycle: it grants at the switch, refreshes on each poll, and expires after
/// the grace period.
public struct BackgroundAudioExemptions: Equatable, Sendable {
    /// How long a silent service keeps the exemption.
    ///
    /// The gap between two tracks is a few seconds, so a short value would end
    /// the exemption between two songs. A user can also pause and resume with
    /// the keyboard media keys without bringing Paguro forward, and that pause
    /// is longer than a track gap. Ninety seconds covers both cases and still
    /// releases a page that stopped for good well inside the idle threshold.
    public static let gracePeriod: TimeInterval = 90

    /// How often the pool asks an exempt service whether it still plays.
    ///
    /// Only exempt services are polled, so the cost is one WebKit query for
    /// each of them. The poll does not need to be exact: it only has to place
    /// the end of playback inside the grace period, which is much longer.
    public static let pollInterval: TimeInterval = 5

    /// The last moment each exempt service was reported as playing.
    private var lastPlaying: [UUID: Date]

    public init(lastPlaying: [UUID: Date] = [:]) {
        self.lastPlaying = lastPlaying
    }

    /// The services that keep their audio now.
    public var exemptServiceIDs: Set<UUID> {
        Set(lastPlaying.keys)
    }

    public var isEmpty: Bool {
        lastPlaying.isEmpty
    }

    public func isExempt(_ serviceID: UUID) -> Bool {
        lastPlaying[serviceID] != nil
    }

    /// Decides one switch. Returns true when the service keeps its audio.
    ///
    /// This is the only route that creates an exemption, so a background page
    /// that starts to play later gains nothing from `refresh`.
    @discardableResult
    public mutating func grantIfPlaying(
        _ serviceID: UUID,
        isPlaying: Bool,
        now: Date
    ) -> Bool {
        guard isPlaying else {
            lastPlaying[serviceID] = nil
            return false
        }
        lastPlaying[serviceID] = now
        return true
    }

    /// Folds one poll answer into an existing exemption.
    ///
    /// A service without an exemption is ignored. A silent answer keeps the
    /// entry, because the grace period, not one poll, decides the end.
    public mutating func refresh(
        _ serviceID: UUID,
        isPlaying: Bool,
        now: Date
    ) {
        guard lastPlaying[serviceID] != nil, isPlaying else { return }
        lastPlaying[serviceID] = now
    }

    /// Ends the exemption of a service that returned to the screen, that the
    /// user stopped, that mute silenced, or that Paguro removed.
    public mutating func revoke(_ serviceID: UUID) {
        lastPlaying[serviceID] = nil
    }

    /// Removes every exemption whose grace period has run out and returns them
    /// in a stable order, so a caller can report each one.
    @discardableResult
    public mutating func expire(now: Date) -> [UUID] {
        let expired = lastPlaying
            .filter { now.timeIntervalSince($0.value) >= Self.gracePeriod }
            .keys
            .sorted { $0.uuidString < $1.uuidString }
        for serviceID in expired {
            lastPlaying[serviceID] = nil
        }
        return expired
    }
}
