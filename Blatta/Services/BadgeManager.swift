import Foundation
import AppKit
import BlattaCore

@MainActor
@Observable
final class BadgeManager {
    /// The true, unmasked unread count per service. Always reflects what the
    /// page actually reported — muting and the per-service show-badge toggle
    /// are applied as a *display mask* (see `maskedIDs`), never by zeroing the
    /// stored count. This keeps `rawCount` meaningful for adaptive polling and
    /// lets un-muting restore the badge instantly without waiting for a poll.
    private(set) var counts: [UUID: Int] = [:]

    /// Services whose badge is hidden because they are muted or have the
    /// show-badge toggle off. Their real count still lives in `counts`.
    private var maskedIDs: Set<UUID> = []

    var doNotDisturb: Bool = false {
        // Mirror into a thread-safe snapshot so the UNUserNotificationCenter
        // delegate can read Do Not Disturb from its callback without asserting
        // main-actor isolation (that callback isn't contractually main-thread;
        // an off-main read via MainActor.assumeIsolated would hard-crash). DND
        // suppresses delivery; it does not hide the unread state.
        didSet { doNotDisturbSnapshot.value = doNotDisturb }
    }

    /// Off-main-safe mirror of `doNotDisturb`. See the property's didSet.
    nonisolated let doNotDisturbSnapshot = AtomicBool(false)

    var showBadgeCountInDock: Bool = true {
        didSet { updateDockBadge() }
    }

    /// Reports the service accounts whose unread count reaches zero. The island
    /// uses this signal to drop the events that the user has read.
    /// `@ObservationIgnored`, because it is a callback and not view state.
    @ObservationIgnored var onUnreadCountCleared: (@MainActor (UUID) -> Void)?

    /// Applies a label to the Dock tile, or removes the badge with nil.
    ///
    /// The default hook writes to AppKit. It is injectable, because the Dock
    /// tile is one process-wide object that a test cannot isolate or read back
    /// reliably: a test replaces this hook to see what the manager asks the
    /// Dock to show. `@ObservationIgnored`, because it is a callback and not
    /// view state.
    @ObservationIgnored var writeDockBadge: @MainActor (String?) -> Void = { label in
        // Use NSApplication.shared rather than the NSApp global — the
        // global is an implicitly-unwrapped optional that can still be
        // nil during early AppState init (and in test hosts), and reading
        // .dockTile through it then traps. NSApplication.shared is lazy
        // and safe even before the run loop is up.
        NSApplication.shared.dockTile.badgeLabel = label
    }

    /// The last state that this manager reported to the log. The Dock badge has
    /// no other diagnostic output, and a poll applies the same label every few
    /// seconds, so the log keeps each change one time only.
    @ObservationIgnored private var lastLoggedDockBadge: String?

    var totalCount: Int {
        return counts.reduce(0) { $0 + (maskedIDs.contains($1.key) ? 0 : $1.value) }
    }

    /// Returns the raw stored count regardless of DND or masking. Used by
    /// adaptive polling to compare deltas without any mask zeroing both sides.
    func rawCount(for instanceID: UUID) -> Int {
        counts[instanceID] ?? 0
    }

    func badgeCount(for instanceID: UUID) -> Int {
        guard !maskedIDs.contains(instanceID) else { return 0 }
        return counts[instanceID] ?? 0
    }

    func aggregateCount(for serviceIDs: [UUID]) -> Int {
        return serviceIDs.reduce(0) { sum, id in
            sum + (maskedIDs.contains(id) ? 0 : (counts[id] ?? 0))
        }
    }

    func updateBadge(for instanceID: UUID, count: Int, isMuted: Bool, showBadge: Bool = true) {
        // Clamp to a sane badge range. The DOM-badge path (catalog badgeJS) is
        // otherwise unbounded, so a page whose expression yields a negative or
        // garbage-large value would corrupt totalCount/aggregateCount — one
        // negative can zero out or hide the dock badge for every other service.
        let clamped = max(0, min(count, 999))
        let previousCount = counts[instanceID] ?? 0
        // Always store the (clamped) true count; muting / show-badge only
        // toggles the display mask. Storing the real value (rather than 0) keeps
        // adaptive polling's delta detection correct for muted services and
        // makes un-muting instantaneous.
        counts[instanceID] = clamped
        if isMuted || !showBadge {
            maskedIDs.insert(instanceID)
        } else {
            maskedIDs.remove(instanceID)
        }
        updateDockBadge()
        // The user read this service account. The mask does not change the
        // stored count, so this test always follows the real unread state.
        if clamped == 0, previousCount > 0 {
            onUnreadCountCleared?(instanceID)
        }
    }

    func removeBadge(for instanceID: UUID) {
        counts.removeValue(forKey: instanceID)
        maskedIDs.remove(instanceID)
        updateDockBadge()
    }

    /// The label that the Dock icon must show now, or nil for no badge.
    var dockBadgeLabel: String? {
        DockBadgePolicy.badgeLabel(
            unreadTotal: totalCount,
            showsBadgeCount: showBadgeCountInDock
        )
    }

    func updateDockBadge() {
        let label = dockBadgeLabel
        writeDockBadge(label)
        logDockBadgeChange(label)
    }

    /// Records each change of the Dock badge.
    ///
    /// A person can see the Dock badge, but no log line explained it. Without
    /// this record, "the Dock shows no badge" cannot separate a zero unread
    /// total, a preference that is off, and a Dock that does not draw the
    /// label that the app applied. The line holds counts only, never a message.
    private func logDockBadgeChange(_ label: String?) {
        let described = label ?? "none"
        let state = "label=\(described) unread=\(totalCount) "
            + "preference=\(showBadgeCountInDock) services=\(counts.count) "
            + "masked=\(maskedIDs.count)"
        // Compare the whole state, not the label alone. Every silent case
        // gives the label "none": no service yet, a table of zeros, and a
        // table that a mask zeroes. Deduplicating on the label made the first
        // "none" at launch hide the later ones for the rest of the run, so the
        // log could not separate those cases at all.
        guard state != lastLoggedDockBadge else { return }
        lastLoggedDockBadge = state
        AppLogger.badges.info("Dock badge changed: \(state, privacy: .public)")
    }
}

/// A minimal thread-safe boolean, so a value owned by a `@MainActor` type can
/// be read safely from a non-isolated context (e.g. a system delegate callback
/// that isn't guaranteed to run on the main thread).
final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ value: Bool) { self._value = value }

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
