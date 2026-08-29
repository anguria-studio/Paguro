import XCTest
import BlattaCore
@testable import Blatta

/// Covers the header download list.
///
/// The tracker holds no WebKit object, so every test drives it with the same
/// plain values that `WebDownloadHandler` reports. No test starts a transfer.
@MainActor
final class DownloadTrackerTests: XCTestCase {
    private let serviceID = UUID()
    private let otherServiceID = UUID()

    /// A fixed clock. The ring delay is a real rule now, so every test that
    /// expects a ring has to say how long its download has been running.
    private let start = Date(timeIntervalSince1970: 2_000_000)
    /// A moment after `DownloadIndicatorState.ringDelay`.
    private var afterDelay: Date { start.addingTimeInterval(1) }
    /// A moment inside the ring delay.
    private var beforeDelay: Date { start.addingTimeInterval(0.2) }

    /// Records a cancel request without a `WKDownload`.
    private final class CancelSpy {
        private(set) var count = 0
        func cancel() { count += 1 }
    }

    // MARK: - State transitions

    func testANewTrackerShowsNothing() {
        let tracker = DownloadTracker()

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
        XCTAssertTrue(tracker.items(for: serviceID).isEmpty)
    }

    func testAStartedDownloadBecomesActiveWithoutAFraction() {
        let tracker = DownloadTracker()
        let id = UUID()

        tracker.begin(id: id, serviceID: serviceID, filename: "report.pdf", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
        XCTAssertEqual(tracker.activeItems(for: serviceID).count, 1)
        XCTAssertEqual(tracker.items(for: serviceID).first?.filename, "report.pdf")
    }

    func testProgressReportsTheCompletedFraction() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "report.pdf", startedAt: start, cancel: {})

        tracker.updateProgress(id: id, received: 512, expected: 2048)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: 0.25, count: 1, unseen: 1))
    }

    func testTwoActiveDownloadsShareOneFraction() {
        let tracker = DownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.begin(id: first, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: second, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        tracker.updateProgress(id: first, received: 100, expected: 200)
        tracker.updateProgress(id: second, received: 100, expected: 200)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: 0.5, count: 2, unseen: 2))
        XCTAssertEqual(tracker.activeItems(for: serviceID).count, 2)
    }

    func testTheDestinationRenamesTheDownload() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "download", startedAt: start, cancel: {})

        tracker.setDestination(
            id: id,
            destination: URL(fileURLWithPath: "/Users/test/Downloads/invoice (1).pdf")
        )

        XCTAssertEqual(tracker.items(for: serviceID).first?.filename, "invoice (1).pdf")
    }

    // MARK: - The record outlives the transfer

    func testAFinishedDownloadKeepsTheIndicatorVisible() {
        let tracker = DownloadTracker()
        let id = UUID()
        let destination = URL(fileURLWithPath: "/Users/test/Downloads/invoice.pdf")
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 10, expected: 100)

        tracker.finish(id: id, destination: destination, at: start)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .resting(count: 1, unseen: 1))
        XCTAssertTrue(tracker.activeItems(for: serviceID).isEmpty)
        XCTAssertEqual(tracker.lastFinishedItem(for: serviceID)?.destination, destination)
    }

    func testAFinishedDownloadFillsItsProgressBar() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 10, expected: 100)

        tracker.finish(id: id, destination: nil, at: start)

        XCTAssertEqual(tracker.items(for: serviceID).first?.fraction, 1)
    }

    func testAFailedDownloadKeepsItsRecordAndItsWarning() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})

        tracker.fail(id: id, at: start)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .failed(count: 1, failedCount: 1, unseen: 1))
        XCTAssertNil(tracker.lastFinishedItem(for: serviceID))
    }

    func testAFailureAmongSuccessesStillWarns() {
        let tracker = DownloadTracker()
        let good = UUID()
        let bad = UUID()
        tracker.begin(id: good, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: bad, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        tracker.finish(id: good, destination: nil, at: start)
        tracker.fail(id: bad, at: start)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .failed(count: 2, failedCount: 1, unseen: 2))
    }

    func testAResultDoesNotChangeAfterTheDownloadEnds() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        tracker.fail(id: id, at: start)
        tracker.updateProgress(id: id, received: 1, expected: 2)

        XCTAssertEqual(tracker.items(for: serviceID).first?.state, .finished)
        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .resting(count: 1, unseen: 1))
    }

    func testAnActiveDownloadWinsOverAFinishedOne() {
        let tracker = DownloadTracker()
        let finished = UUID()
        let running = UUID()
        tracker.begin(id: finished, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: finished, destination: nil, at: start)

        tracker.begin(id: running, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: running, received: 3, expected: 4)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: 0.75, count: 2, unseen: 2))
    }

    // MARK: - The ring delay

    func testAStartedDownloadRecordsWhenItBegan() {
        let tracker = DownloadTracker()
        let id = UUID()

        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.items(for: serviceID).first?.startedAt, start)
    }

    func testAFastDownloadStaysHiddenWhileItRuns() {
        let tracker = DownloadTracker()
        let id = UUID()

        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 10, expected: 100)

        XCTAssertEqual(tracker.state(for: serviceID, now: beforeDelay), .hidden)
        // The record is live the whole time, so the progress ticker keeps
        // reading it and wakes the header when the delay passes.
        XCTAssertEqual(tracker.activeItems(for: serviceID).count, 1)
    }

    func testAFastDownloadGoesStraightToARestingCount() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        XCTAssertEqual(tracker.state(for: serviceID, now: beforeDelay), .hidden)

        tracker.finish(id: id, destination: nil, at: start)

        let state = tracker.state(for: serviceID, now: beforeDelay)
        XCTAssertEqual(state, .resting(count: 1, unseen: 1))
        XCTAssertEqual(state.badgeText, "1")
    }

    func testASlowDownloadShowsItsRingAfterTheDelay() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 25, expected: 100)

        XCTAssertEqual(tracker.state(for: serviceID, now: beforeDelay), .hidden)
        XCTAssertEqual(
            tracker.state(
                for: serviceID,
                now: start.addingTimeInterval(DownloadIndicatorState.ringDelay.seconds)
            ),
            .active(fraction: 0.25, count: 1, unseen: 1)
        )
    }

    func testANewDownloadDoesNotFlashARingOverAFinishedRecord() {
        let tracker = DownloadTracker()
        let done = UUID()
        let fresh = UUID()
        tracker.begin(id: done, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: done, destination: nil, at: start)

        tracker.begin(id: fresh, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.state(for: serviceID, now: beforeDelay), .resting(count: 2, unseen: 2))
        XCTAssertEqual(
            tracker.state(for: serviceID, now: afterDelay),
            .active(fraction: nil, count: 2, unseen: 2)
        )
    }

    func testANewDownloadDoesNotFlashARingOverAFailedRecord() {
        let tracker = DownloadTracker()
        let broken = UUID()
        let fresh = UUID()
        tracker.begin(id: broken, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.fail(id: broken, at: start)

        tracker.begin(id: fresh, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        XCTAssertEqual(
            tracker.state(for: serviceID, now: beforeDelay),
            .failed(count: 2, failedCount: 1, unseen: 2)
        )
    }

    func testTheOldestRunningDownloadDecidesTheRing() {
        let tracker = DownloadTracker()
        let older = UUID()
        let newer = UUID()
        tracker.begin(id: older, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(
            id: newer,
            serviceID: serviceID,
            filename: "b.zip",
            startedAt: start.addingTimeInterval(0.9),
            cancel: {}
        )

        // The newer download is younger than the delay, but the older one has
        // already earned the ring for the pair.
        XCTAssertEqual(
            tracker.state(for: serviceID, now: afterDelay),
            .active(fraction: nil, count: 2, unseen: 2)
        )
    }

    // MARK: - The badge window

    /// A moment after `DownloadIndicatorState.badgeWindow`.
    private var afterBadgeWindow: Date { start.addingTimeInterval(13) }

    func testAResultCountsTowardTheBadgeInsideItsWindow() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: start.addingTimeInterval(11)), 1)
        XCTAssertEqual(
            tracker.state(for: serviceID, now: start.addingTimeInterval(11)).badgeText,
            "1"
        )
    }

    func testTheBadgeClearsAfterItsWindowAndTheControlStays() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        let state = tracker.state(for: serviceID, now: afterBadgeWindow)

        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterBadgeWindow), 0)
        XCTAssertNil(state.badgeText)
        // Point of the change: the record and its route to the file remain.
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state, .resting(count: 1, unseen: 0))
        XCTAssertEqual(tracker.items(for: serviceID).count, 1)
    }

    func testTheWindowBoundaryStopsTheCount() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        let window = DownloadIndicatorState.badgeWindow.seconds
        XCTAssertEqual(
            tracker.unseenCount(for: serviceID, now: start.addingTimeInterval(window - 0.01)),
            1
        )
        XCTAssertEqual(
            tracker.unseenCount(for: serviceID, now: start.addingTimeInterval(window)),
            0
        )
    }

    func testOpeningTheListAcknowledgesEveryResult() {
        let tracker = DownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.begin(id: first, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: second, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: first, destination: nil, at: start)
        tracker.fail(id: second, at: start)
        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterDelay), 2)

        tracker.acknowledgeAll(for: serviceID)

        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterDelay), 0)
        XCTAssertNil(tracker.state(for: serviceID, now: afterDelay).badgeText)
        XCTAssertEqual(tracker.items(for: serviceID).count, 2)
    }

    func testOpeningTheListLeavesARunningDownloadUnseen() {
        let tracker = DownloadTracker()
        let running = UUID()
        tracker.begin(id: running, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.acknowledgeAll(for: serviceID)

        // The user cannot have seen a result that has not happened yet.
        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterDelay), 1)

        tracker.finish(id: running, destination: nil, at: start)

        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterDelay), 1)
        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay).badgeText, "1")
    }

    func testOpeningTheListLeavesAnotherServiceAlone() {
        let tracker = DownloadTracker()
        let mine = UUID()
        let theirs = UUID()
        tracker.begin(id: mine, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: theirs, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: mine, destination: nil, at: start)
        tracker.finish(id: theirs, destination: nil, at: start)

        tracker.acknowledgeAll(for: serviceID)

        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterDelay), 0)
        XCTAssertEqual(tracker.unseenCount(for: otherServiceID, now: afterDelay), 1)
    }

    func testEveryRunningDownloadCountsWhileItRuns() {
        let tracker = DownloadTracker()
        for index in 0..<3 {
            tracker.begin(
                id: UUID(),
                serviceID: serviceID,
                filename: "a-\(index).zip",
                startedAt: start,
                cancel: {}
            )
        }

        // No download has finished, and the badge already reports all three.
        XCTAssertEqual(tracker.unseenCount(for: serviceID, now: afterDelay), 3)
        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay).badgeText, "3")
    }

    func testASeenResultAndANewArrivalCountSeparately() {
        let tracker = DownloadTracker()
        let old = UUID()
        let new = UUID()
        tracker.begin(id: old, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: old, destination: nil, at: start)
        tracker.acknowledgeAll(for: serviceID)

        tracker.begin(id: new, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: new, destination: nil, at: start)

        let state = tracker.state(for: serviceID, now: afterDelay)
        XCTAssertEqual(state, .resting(count: 2, unseen: 1))
        XCTAssertEqual(state.badgeText, "1")
    }

    // MARK: - Dismiss and clear

    func testDismissRemovesAnEndedRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        tracker.dismiss(id: id)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
        XCTAssertTrue(tracker.items(for: serviceID).isEmpty)
    }

    func testDismissRemovesAFailedRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.fail(id: id, at: start)

        tracker.dismiss(id: id)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
    }

    func testDismissLeavesARunningDownloadInPlace() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.dismiss(id: id)

        XCTAssertEqual(tracker.activeItems(for: serviceID).count, 1)
        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
    }

    func testClearRemovesEndedRecordsAndKeepsRunningOnes() {
        let tracker = DownloadTracker()
        let done = UUID()
        let broken = UUID()
        let running = UUID()
        tracker.begin(id: done, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: broken, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.begin(id: running, serviceID: serviceID, filename: "c.zip", startedAt: start, cancel: {})
        tracker.finish(id: done, destination: nil, at: start)
        tracker.fail(id: broken, at: start)

        tracker.clear(for: serviceID)

        XCTAssertEqual(tracker.items(for: serviceID).map(\.id), [running])
        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
    }

    func testClearLeavesAnotherServiceAlone() {
        let tracker = DownloadTracker()
        let mine = UUID()
        let theirs = UUID()
        tracker.begin(id: mine, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: theirs, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: mine, destination: nil, at: start)
        tracker.finish(id: theirs, destination: nil, at: start)

        tracker.clear(for: serviceID)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
        XCTAssertEqual(tracker.state(for: otherServiceID, now: afterDelay), .resting(count: 1, unseen: 1))
    }

    func testTheClearActionAppearsOnlyForAnEndedRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        XCTAssertFalse(tracker.hasDismissibleItems(for: serviceID))

        tracker.finish(id: id, destination: nil, at: start)

        XCTAssertTrue(tracker.hasDismissibleItems(for: serviceID))
    }

    func testRevealingAFileKeepsItsRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(
            id: id,
            destination: URL(fileURLWithPath: "/Users/test/Downloads/a.zip"),
            at: start
        )
        guard let item = tracker.lastFinishedItem(for: serviceID) else {
            return XCTFail("The finished record is missing")
        }

        tracker.revealInFinder(item)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .resting(count: 1, unseen: 1))
    }

    // MARK: - Cancellation

    func testCancelCallsTheStoredActionOnlyOnce() {
        let tracker = DownloadTracker()
        let id = UUID()
        let spy = CancelSpy()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start) { spy.cancel() }

        tracker.cancel(id: id)
        tracker.cancel(id: id)

        XCTAssertEqual(spy.count, 1)
    }

    func testAStoppedDownloadLeavesNoRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})

        tracker.markCancelled(id: id)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
        XCTAssertTrue(tracker.items(for: serviceID).isEmpty)
    }

    func testCancelAllStopsOnlyTheRequestedService() {
        let tracker = DownloadTracker()
        let mine = CancelSpy()
        let theirs = CancelSpy()
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "a.zip", startedAt: start) { mine.cancel() }
        tracker.begin(id: UUID(), serviceID: otherServiceID, filename: "b.zip", startedAt: start) { theirs.cancel() }

        tracker.cancelAll(for: serviceID)

        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(theirs.count, 0)
    }

    // MARK: - Service scope

    func testAnotherServicesDownloadStaysOutOfThisHeader() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: otherServiceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 1, expected: 2)

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
        XCTAssertEqual(tracker.state(for: otherServiceID, now: afterDelay), .active(fraction: 0.5, count: 1, unseen: 1))
    }

    func testADownloadWithoutAServiceAppearsInEveryHeader() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: nil, filename: "a.zip", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
        XCTAssertEqual(tracker.state(for: otherServiceID, now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
    }

    func testTheListShowsTheNewestDownloadFirst() {
        let tracker = DownloadTracker()
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "first.zip", startedAt: start, cancel: {})
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "second.zip", startedAt: start, cancel: {})

        XCTAssertEqual(
            tracker.items(for: serviceID).map(\.filename),
            ["second.zip", "first.zip"]
        )
    }

    // MARK: - Session scope

    func testStopDropsEverySessionRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        tracker.stop()

        XCTAssertEqual(tracker.state(for: serviceID, now: afterDelay), .hidden)
        XCTAssertTrue(tracker.items.isEmpty)
    }

    func testTheHistoryDropsOldRecordsAndKeepsActiveDownloads() {
        let tracker = DownloadTracker()
        let running = UUID()
        tracker.begin(id: running, serviceID: serviceID, filename: "running.zip", startedAt: start, cancel: {})

        for index in 0..<40 {
            let id = UUID()
            tracker.begin(id: id, serviceID: serviceID, filename: "done-\(index).zip", startedAt: start, cancel: {})
            tracker.finish(id: id, destination: nil, at: start)
        }

        XCTAssertLessThanOrEqual(tracker.items.count, 25)
        XCTAssertEqual(tracker.activeItems(for: serviceID).map(\.id), [running])
    }

    // MARK: - Handler rules

    func testTheHandlerReadsAStopAsACancellation() {
        let cancelled = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: nil
        )
        let offline = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: nil
        )

        XCTAssertTrue(WebDownloadHandler.isCancellation(cancelled))
        XCTAssertFalse(WebDownloadHandler.isCancellation(offline))
    }
}
