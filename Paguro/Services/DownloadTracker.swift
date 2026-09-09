import AppKit
import PaguroCore
import Foundation

/// Keeps the download records that the content header shows.
///
/// `WebDownloadHandler` owns the WebKit objects and reports plain values here.
/// The tracker therefore holds no `WKDownload`, so tests can drive every state
/// change without a network transfer.
///
/// Records live in memory for the current app run only. Nothing reaches the
/// content store, and `AppState.shutdown()` drops them with the process. The
/// island's recent list uses the same model.
///
/// A record leaves the list in one of three ways:
///
/// 1. The user dismisses an ended record with `dismiss(id:)`.
/// 2. The user clears every ended record of a service with `clear(for:)`.
/// 3. The user stops a running download with `cancel(id:)`.
///
/// A stop withdraws the download, so it removes the record instead of leaving
/// a result. A dismiss therefore never applies to a running download: its row
/// offers the stop action instead. Showing a file in the Finder reads the
/// record and keeps it.
@MainActor
@Observable
final class DownloadTracker {

    /// One download that Paguro started for a service.
    struct Item: Identifiable, Equatable {
        enum State: Equatable {
            case active
            case finished
            case failed

            var isActive: Bool { self == .active }

            /// Whether the user can remove this record from the list.
            var isDismissible: Bool { self != .active }
        }

        let id: UUID
        /// The service that started the download. It is nil when Paguro cannot
        /// attribute the download to one service.
        let serviceID: UUID?
        /// When the download started. The indicator uses it to hold the ring
        /// back until a download has run for `ringDelay`.
        let startedAt: Date
        var filename: String
        var receivedBytes: Int64
        /// Zero or less means that the server gave no size.
        var expectedBytes: Int64
        var state: State
        var destination: URL?
        /// When the download reached its result. It is nil while it runs.
        var endedAt: Date?
        /// Whether the user has seen this result. Opening the list sets it.
        var acknowledged = false

        /// The completed part of this download, or nil for an unknown size.
        var fraction: Double? {
            guard expectedBytes > 0 else { return nil }
            return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
        }
    }

    /// How many records the tracker keeps for the current app run. The oldest
    /// ended record leaves first, so a long session cannot grow without a limit.
    private static let historyLimit = 25

    private(set) var items: [Item] = []

    /// Cancel actions for the active downloads. `WKDownload` is not a value, so
    /// it stays behind this closure.
    @ObservationIgnored private var cancelActions: [UUID: () -> Void] = [:]

    /// One wake task for each download that has not yet reached `ringDelay`.
    @ObservationIgnored private var ringDelayTasks: [UUID: Task<Void, Never>] = [:]

    /// One wake task for each result that still counts toward the badge.
    @ObservationIgnored private var badgeWindowTasks: [UUID: Task<Void, Never>] = [:]

    /// Changes when a timed rule reaches its moment.
    ///
    /// Two rules run on a clock: a download becomes old enough for a ring, and
    /// a result stops being news. `state(for:now:)` reads this value, so the
    /// header re-reads the rules at each of those moments even though no
    /// record changed.
    private(set) var wakeTick = 0

    init() {}

    // MARK: - Download lifetime

    /// Records a new download and its cancel action.
    func begin(
        id: UUID,
        serviceID: UUID?,
        filename: String,
        startedAt: Date = Date(),
        cancel: @escaping () -> Void
    ) {
        items.removeAll { $0.id == id }
        items.append(
            Item(
                id: id,
                serviceID: serviceID,
                startedAt: startedAt,
                filename: filename,
                receivedBytes: 0,
                expectedBytes: 0,
                state: .active,
                destination: nil,
                endedAt: nil
            )
        )
        cancelActions[id] = cancel
        scheduleRingDelayWake(for: id)
        trimHistory()
    }

    /// Refreshes the header when this download becomes old enough for a ring.
    ///
    /// The progress ticker in `WebDownloadHandler` runs through the whole
    /// transfer, but it writes only when a byte count changes. A download that
    /// stalls before the delay would therefore never wake the header. This
    /// one-shot task closes that gap. Each download has its own task, so a
    /// second download cannot postpone the first one's ring.
    private func scheduleRingDelayWake(for id: UUID) {
        ringDelayTasks[id]?.cancel()
        ringDelayTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: DownloadIndicatorState.ringDelay)
            guard !Task.isCancelled else { return }
            self?.ringDelayTasks.removeValue(forKey: id)
            self?.wakeTick &+= 1
        }
    }

    private func cancelRingDelayWake(for id: UUID) {
        ringDelayTasks.removeValue(forKey: id)?.cancel()
    }

    /// Refreshes the header when this result stops counting toward the badge.
    ///
    /// Nothing else changes at that moment, so without this task a badge would
    /// sit at its old value until the next download.
    private func scheduleBadgeWindowWake(for id: UUID) {
        badgeWindowTasks[id]?.cancel()
        badgeWindowTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: DownloadIndicatorState.badgeWindow)
            guard !Task.isCancelled else { return }
            self?.badgeWindowTasks.removeValue(forKey: id)
            self?.wakeTick &+= 1
        }
    }

    private func cancelBadgeWindowWake(for id: UUID) {
        badgeWindowTasks.removeValue(forKey: id)?.cancel()
    }

    /// Marks every ended record of one service as seen. The header calls this
    /// when the user opens the download list.
    ///
    /// A running download keeps its unseen state on purpose. The user cannot
    /// have seen a result that has not happened, so its completion is still
    /// news when it arrives.
    func acknowledgeAll(for serviceID: UUID?) {
        for index in items.indices where matches(items[index], serviceID: serviceID) {
            guard !items[index].state.isActive, !items[index].acknowledged else { continue }
            items[index].acknowledged = true
            cancelBadgeWindowWake(for: items[index].id)
        }
    }

    /// Records the chosen destination. WebKit reports the final name after the
    /// download starts, so the first name can be a guess from the request URL.
    func setDestination(id: UUID, destination: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].destination = destination
        items[index].filename = destination.lastPathComponent
    }

    /// Records the current byte counts of one active download.
    func updateProgress(id: UUID, received: Int64, expected: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].state.isActive else { return }
        guard items[index].receivedBytes != received
            || items[index].expectedBytes != expected else { return }
        items[index].receivedBytes = received
        items[index].expectedBytes = expected
    }

    func finish(id: UUID, destination: URL?, at date: Date = Date()) {
        end(id: id, state: .finished, destination: destination, at: date)
    }

    func fail(id: UUID, at date: Date = Date()) {
        end(id: id, state: .failed, destination: nil, at: date)
    }

    /// Removes the record of a download that stopped before it ended.
    ///
    /// The user asked for the stop, so the list reports nothing about it.
    func markCancelled(id: UUID) {
        cancelActions.removeValue(forKey: id)
        cancelRingDelayWake(for: id)
        cancelBadgeWindowWake(for: id)
        items.removeAll { $0.id == id }
    }

    /// Stops one active download. WebKit then reports the failure, and that
    /// callback removes the record.
    func cancel(id: UUID) {
        guard let action = cancelActions[id] else { return }
        action()
        cancelActions.removeValue(forKey: id)
    }

    /// Stops every active download of one service.
    func cancelAll(for serviceID: UUID?) {
        for item in activeItems(for: serviceID) {
            cancel(id: item.id)
        }
    }

    private func end(id: UUID, state: Item.State, destination: URL?, at date: Date) {
        cancelActions.removeValue(forKey: id)
        cancelRingDelayWake(for: id)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].state.isActive else { return }
        items[index].state = state
        items[index].endedAt = date
        if let destination {
            items[index].destination = destination
            items[index].filename = destination.lastPathComponent
        }
        if items[index].expectedBytes > 0, state == .finished {
            items[index].receivedBytes = items[index].expectedBytes
        }
        scheduleBadgeWindowWake(for: id)
    }

    // MARK: - List actions

    /// Removes one ended record.
    ///
    /// A running download keeps its record, because its row offers the stop
    /// action instead of a dismiss action.
    func dismiss(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.state.isDismissible else { return }
        cancelBadgeWindowWake(for: id)
        items.removeAll { $0.id == id }
    }

    /// Removes every ended record of one service and keeps its running
    /// downloads.
    func clear(for serviceID: UUID?) {
        for item in items where matches(item, serviceID: serviceID) && item.state.isDismissible {
            cancelBadgeWindowWake(for: item.id)
        }
        items.removeAll { matches($0, serviceID: serviceID) && $0.state.isDismissible }
    }

    /// Whether the list of one service has a record that the user can remove.
    func hasDismissibleItems(for serviceID: UUID?) -> Bool {
        items.contains { matches($0, serviceID: serviceID) && $0.state.isDismissible }
    }

    /// Keeps the newest records and drops the oldest ended ones.
    private func trimHistory() {
        guard items.count > Self.historyLimit else { return }
        var remaining = items.count - Self.historyLimit
        items.removeAll { item in
            guard remaining > 0, item.state.isDismissible else { return false }
            remaining -= 1
            cancelBadgeWindowWake(for: item.id)
            return true
        }
    }

    // MARK: - Queries

    /// Whether a download belongs to the header of one service.
    ///
    /// A download without a service belongs to every header, so a download that
    /// Paguro cannot attribute stays visible instead of disappearing.
    private func matches(_ item: Item, serviceID: UUID?) -> Bool {
        item.serviceID == nil || item.serviceID == serviceID
    }

    /// The downloads of one service, newest first.
    func items(for serviceID: UUID?) -> [Item] {
        Array(items.filter { matches($0, serviceID: serviceID) }.reversed())
    }

    /// The running downloads of one service, newest first.
    func activeItems(for serviceID: UUID?) -> [Item] {
        items(for: serviceID).filter(\.state.isActive)
    }

    /// The newest finished download of one service.
    func lastFinishedItem(for serviceID: UUID?) -> Item? {
        items(for: serviceID).first { $0.state == .finished }
    }

    /// The indicator state for one service.
    ///
    /// This is where the clock is read. `DownloadIndicatorState` stays a pure
    /// function, so the elapsed value arrives as an argument.
    func state(for serviceID: UUID?, now: Date = Date()) -> DownloadIndicatorState {
        // Reading the tick registers this call with the observation system, so
        // the header refreshes when a timed rule reaches its moment.
        _ = wakeTick

        let owned = items.filter { matches($0, serviceID: serviceID) }
        var totals = DownloadProgressTotals()
        var failedCount = 0
        var unseenCount = 0
        var oldestActiveStart: Date?

        for item in owned {
            switch item.state {
            case .active:
                totals.activeCount += 1
                totals.receivedBytes += max(0, item.receivedBytes)
                if item.expectedBytes > 0 {
                    totals.expectedBytes += item.expectedBytes
                }
                if oldestActiveStart == nil || item.startedAt < oldestActiveStart! {
                    oldestActiveStart = item.startedAt
                }
            case .failed:
                failedCount += 1
            case .finished:
                break
            }

            if isUnseen(item, now: now) { unseenCount += 1 }
        }

        return DownloadIndicatorState.resolve(
            totals: totals,
            recordCount: owned.count,
            unseenCount: unseenCount,
            failedCount: failedCount,
            longestActiveElapsed: oldestActiveStart.map {
                .seconds(max(0, now.timeIntervalSince($0)))
            }
        )
    }

    /// Whether one record still counts toward the badge.
    ///
    /// A running download always counts, so several transfers at once report
    /// their number before any of them finishes. A result counts until the
    /// user opens the list or `badgeWindow` passes, whichever comes first.
    private func isUnseen(_ item: Item, now: Date) -> Bool {
        guard !item.state.isActive else { return true }
        guard !item.acknowledged, let endedAt = item.endedAt else { return false }
        return .seconds(max(0, now.timeIntervalSince(endedAt)))
            < DownloadIndicatorState.badgeWindow
    }

    /// The badge count for one service, for callers that need only that value.
    func unseenCount(for serviceID: UUID?, now: Date = Date()) -> Int {
        items.filter { matches($0, serviceID: serviceID) && isUnseen($0, now: now) }.count
    }

    // MARK: - Finder

    /// Selects a finished file in the Finder. The record stays in the list.
    func revealInFinder(_ item: Item) {
        guard item.state == .finished, let destination = item.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Drops the session records and the pending cancel actions.
    /// `AppState.shutdown()` calls this.
    func stop() {
        cancelActions.removeAll()
        for task in ringDelayTasks.values { task.cancel() }
        ringDelayTasks.removeAll()
        for task in badgeWindowTasks.values { task.cancel() }
        badgeWindowTasks.removeAll()
        items.removeAll()
    }
}
