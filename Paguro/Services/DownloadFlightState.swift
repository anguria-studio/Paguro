import PaguroCore
import SwiftUI

/// The marks that fly from the web content into the header download control.
///
/// The state lives beside `DownloadTracker` instead of inside a view, because
/// the mark and the control it lands on sit in different parts of the window.
/// The mark reports the start; the control keeps the count. `AppState` owns one
/// instance, so both views read the same flights.
///
/// `DownloadFlightPlanner` in `PaguroCore` holds the rule that decides how many
/// marks a group of starts produces. This type adds only what needs the app: the
/// spoken announcement, the wait for a control that is not in the header yet,
/// and the handoff to the control.
@MainActor
@Observable
final class DownloadFlightState {

    /// One mark on its way to the control.
    struct Flight: Identifiable, Equatable {
        let id: Int
        /// How long the mark waits before it leaves its start place.
        let delay: Duration
    }

    /// The marks on the way. The overlay draws one view for each of them.
    private(set) var flights: [Flight] = []

    /// Grows each time a mark reaches the control.
    ///
    /// `DownloadIndicatorButton` observes it and plays its own movement, so one
    /// handoff ends in the control instead of in the overlay.
    private(set) var arrivalTick = 0

    @ObservationIgnored private var planner = DownloadFlightPlanner()
    /// One end task for each mark that never reached the control.
    @ObservationIgnored private var waitTasks: [Int: Task<Void, Never>] = [:]
    /// The newest start this state has answered, so one start sends one mark.
    @ObservationIgnored private var answeredSequence = 0

    init() {}

    /// Answers one download start.
    ///
    /// The caller filters the starts that must not animate: a start in another
    /// service, and any start that happens while no window shows the content.
    /// This method then decides how the start appears.
    func start(
        _ event: DownloadTracker.StartEvent,
        reduceMotion: Bool,
        at now: Date = Date()
    ) {
        // A repeated report of the same start changes nothing. The sequence
        // grows for a real new download only.
        guard event.sequence > answeredSequence else { return }
        answeredSequence = event.sequence

        guard case let .launch(flightID, delay) = planner.plan(startedAt: now) else {
            // The start joined a mark already on the way, or it met the limit.
            // The header badge counts it either way.
            return
        }

        AccessibilityNotification
            .Announcement(DownloadIndicatorState.startAnnouncement(filename: event.filename))
            .post()

        guard DownloadStartCue.resolve(reduceMotion: reduceMotion).hasTravel else {
            // Reduce Motion has no travel. The control itself carries the cue,
            // so the mark never leaves and the arrival happens at once. The
            // flight stays with the planner for its group window, so a group of
            // starts produces one fade instead of a row of them.
            arrivalTick &+= 1
            scheduleEnd(of: flightID, after: DownloadFlightPlanner.coalesceWindow)
            return
        }

        flights.append(Flight(id: flightID, delay: delay))
        scheduleEnd(
            of: flightID,
            after: DownloadIndicatorMotion.flightDestinationWait
                + DownloadIndicatorMotion.flightTotal
        )
    }

    /// Ends one mark at the control.
    ///
    /// The overlay calls it when the travel finishes, so the control plays its
    /// part of the handoff in the same moment the mark disappears.
    func arrive(flightID: Int) {
        guard flights.contains(where: { $0.id == flightID }) else { return }
        remove(flightID)
        arrivalTick &+= 1
    }

    /// Drops every mark and its end task. `AppState.shutdown()` calls it.
    func stop() {
        for task in waitTasks.values { task.cancel() }
        waitTasks.removeAll()
        flights.removeAll()
        planner.forgetAll()
    }

    /// Gives one mark a last moment, whatever happens to it.
    ///
    /// A mark waits for its destination: the first download of a service has no
    /// control in the header yet, because the indicator earns its place after
    /// the ring delay. A download that the user stops inside that time never
    /// gives the control a place, so the mark needs an end of its own. Nothing
    /// lands then, so the control plays nothing.
    private func scheduleEnd(of flightID: Int, after wait: Duration) {
        waitTasks[flightID]?.cancel()
        waitTasks[flightID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.remove(flightID)
        }
    }

    private func remove(_ flightID: Int) {
        waitTasks.removeValue(forKey: flightID)?.cancel()
        flights.removeAll { $0.id == flightID }
        planner.forget(flightID: flightID)
    }
}
