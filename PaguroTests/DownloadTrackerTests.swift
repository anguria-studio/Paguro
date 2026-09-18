import XCTest
import PaguroCore
@testable import Paguro

/// Covers the global download list behind the header control.
///
/// Every query answers the downloads of every service, so no test passes a
/// service to one. `serviceID` and `otherServiceID` are the sources of the
/// records, which each row still names.
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

        XCTAssertEqual(tracker.state(now: afterDelay), .hidden)
        XCTAssertTrue(tracker.recentItems.isEmpty)
    }

    func testAStartedDownloadBecomesActiveWithoutAFraction() {
        let tracker = DownloadTracker()
        let id = UUID()

        tracker.begin(id: id, serviceID: serviceID, filename: "report.pdf", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
        XCTAssertEqual(tracker.activeItems.count, 1)
        XCTAssertEqual(tracker.recentItems.first?.filename, "report.pdf")
    }

    func testProgressReportsTheCompletedFraction() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "report.pdf", startedAt: start, cancel: {})

        tracker.updateProgress(id: id, received: 512, expected: 2048)

        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: 0.25, count: 1, unseen: 1))
    }

    func testTwoActiveDownloadsShareOneFraction() {
        let tracker = DownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.begin(id: first, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: second, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        tracker.updateProgress(id: first, received: 100, expected: 200)
        tracker.updateProgress(id: second, received: 100, expected: 200)

        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: 0.5, count: 2, unseen: 2))
        XCTAssertEqual(tracker.activeItems.count, 2)
    }

    func testTheDestinationRenamesTheDownload() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "download", startedAt: start, cancel: {})

        tracker.setDestination(
            id: id,
            destination: URL(fileURLWithPath: "/Users/test/Downloads/invoice (1).pdf")
        )

        XCTAssertEqual(tracker.recentItems.first?.filename, "invoice (1).pdf")
    }

    // MARK: - The record outlives the transfer

    func testAFinishedDownloadKeepsTheIndicatorVisible() {
        let tracker = DownloadTracker()
        let id = UUID()
        let destination = URL(fileURLWithPath: "/Users/test/Downloads/invoice.pdf")
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 10, expected: 100)

        tracker.finish(id: id, destination: destination, at: start)

        XCTAssertEqual(tracker.state(now: afterDelay), .resting(count: 1, unseen: 1))
        XCTAssertTrue(tracker.activeItems.isEmpty)
        XCTAssertEqual(tracker.lastFinishedItem?.destination, destination)
    }

    func testAFinishedDownloadFillsItsProgressBar() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 10, expected: 100)

        tracker.finish(id: id, destination: nil, at: start)

        XCTAssertEqual(tracker.recentItems.first?.fraction, 1)
    }

    func testAFailedDownloadKeepsItsRecordAndItsWarning() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})

        tracker.fail(id: id, at: start)

        XCTAssertEqual(tracker.state(now: afterDelay), .failed(count: 1, failedCount: 1, unseen: 1))
        XCTAssertNil(tracker.lastFinishedItem)
    }

    func testAFailureAmongSuccessesStillWarns() {
        let tracker = DownloadTracker()
        let good = UUID()
        let bad = UUID()
        tracker.begin(id: good, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: bad, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        tracker.finish(id: good, destination: nil, at: start)
        tracker.fail(id: bad, at: start)

        XCTAssertEqual(tracker.state(now: afterDelay), .failed(count: 2, failedCount: 1, unseen: 2))
    }

    func testAResultDoesNotChangeAfterTheDownloadEnds() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "invoice.pdf", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        tracker.fail(id: id, at: start)
        tracker.updateProgress(id: id, received: 1, expected: 2)

        XCTAssertEqual(tracker.recentItems.first?.state, .finished)
        XCTAssertEqual(tracker.state(now: afterDelay), .resting(count: 1, unseen: 1))
    }

    func testAnActiveDownloadWinsOverAFinishedOne() {
        let tracker = DownloadTracker()
        let finished = UUID()
        let running = UUID()
        tracker.begin(id: finished, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: finished, destination: nil, at: start)

        tracker.begin(id: running, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: running, received: 3, expected: 4)

        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: 0.75, count: 2, unseen: 2))
    }

    // MARK: - The ring delay

    func testAStartedDownloadRecordsWhenItBegan() {
        let tracker = DownloadTracker()
        let id = UUID()

        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.recentItems.first?.startedAt, start)
    }

    func testAFastDownloadStaysHiddenWhileItRuns() {
        let tracker = DownloadTracker()
        let id = UUID()

        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 10, expected: 100)

        XCTAssertEqual(tracker.state(now: beforeDelay), .hidden)
        // The record is live the whole time, so the progress ticker keeps
        // reading it and wakes the header when the delay passes.
        XCTAssertEqual(tracker.activeItems.count, 1)
    }

    func testAFastDownloadGoesStraightToARestingCount() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        XCTAssertEqual(tracker.state(now: beforeDelay), .hidden)

        tracker.finish(id: id, destination: nil, at: start)

        let state = tracker.state(now: beforeDelay)
        XCTAssertEqual(state, .resting(count: 1, unseen: 1))
        XCTAssertEqual(state.badgeText, "1")
    }

    func testASlowDownloadShowsItsRingAfterTheDelay() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.updateProgress(id: id, received: 25, expected: 100)

        XCTAssertEqual(tracker.state(now: beforeDelay), .hidden)
        XCTAssertEqual(
            tracker.state(
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

        XCTAssertEqual(tracker.state(now: beforeDelay), .resting(count: 2, unseen: 2))
        XCTAssertEqual(
            tracker.state(now: afterDelay),
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
            tracker.state(now: beforeDelay),
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
            tracker.state(now: afterDelay),
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

        XCTAssertEqual(tracker.unseenCount(now: start.addingTimeInterval(11)), 1)
        XCTAssertEqual(
            tracker.state(now: start.addingTimeInterval(11)).badgeText,
            "1"
        )
    }

    func testTheBadgeClearsAfterItsWindowAndTheControlStays() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        let state = tracker.state(now: afterBadgeWindow)

        XCTAssertEqual(tracker.unseenCount(now: afterBadgeWindow), 0)
        XCTAssertNil(state.badgeText)
        // Point of the change: the record and its route to the file remain.
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state, .resting(count: 1, unseen: 0))
        XCTAssertEqual(tracker.recentItems.count, 1)
    }

    func testTheWindowBoundaryStopsTheCount() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        let window = DownloadIndicatorState.badgeWindow.seconds
        XCTAssertEqual(
            tracker.unseenCount(now: start.addingTimeInterval(window - 0.01)),
            1
        )
        XCTAssertEqual(
            tracker.unseenCount(now: start.addingTimeInterval(window)),
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
        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 2)

        tracker.acknowledgeAll()

        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 0)
        XCTAssertNil(tracker.state(now: afterDelay).badgeText)
        XCTAssertEqual(tracker.recentItems.count, 2)
    }

    func testOpeningTheListLeavesARunningDownloadUnseen() {
        let tracker = DownloadTracker()
        let running = UUID()
        tracker.begin(id: running, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.acknowledgeAll()

        // The user cannot have seen a result that has not happened yet.
        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 1)

        tracker.finish(id: running, destination: nil, at: start)

        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 1)
        XCTAssertEqual(tracker.state(now: afterDelay).badgeText, "1")
    }

    /// The list holds every service, so the user sees every result in it.
    func testOpeningTheListAcknowledgesEveryService() {
        let tracker = DownloadTracker()
        let mine = UUID()
        let theirs = UUID()
        tracker.begin(id: mine, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: theirs, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: mine, destination: nil, at: start)
        tracker.finish(id: theirs, destination: nil, at: start)
        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 2)

        tracker.acknowledgeAll()

        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 0)
        XCTAssertNil(tracker.state(now: afterDelay).badgeText)
        XCTAssertEqual(tracker.recentItems.count, 2)
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
        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 3)
        XCTAssertEqual(tracker.state(now: afterDelay).badgeText, "3")
    }

    func testASeenResultAndANewArrivalCountSeparately() {
        let tracker = DownloadTracker()
        let old = UUID()
        let new = UUID()
        tracker.begin(id: old, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: old, destination: nil, at: start)
        tracker.acknowledgeAll()

        tracker.begin(id: new, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: new, destination: nil, at: start)

        let state = tracker.state(now: afterDelay)
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

        XCTAssertEqual(tracker.state(now: afterDelay), .hidden)
        XCTAssertTrue(tracker.recentItems.isEmpty)
    }

    func testDismissRemovesAFailedRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.fail(id: id, at: start)

        tracker.dismiss(id: id)

        XCTAssertEqual(tracker.state(now: afterDelay), .hidden)
    }

    func testDismissLeavesARunningDownloadInPlace() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.dismiss(id: id)

        XCTAssertEqual(tracker.activeItems.count, 1)
        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
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

        tracker.clear()

        XCTAssertEqual(tracker.recentItems.map(\.id), [running])
        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
    }

    /// Clear empties the whole list, because the whole list is what the user
    /// reads.
    func testClearRemovesTheEndedRecordsOfEveryService() {
        let tracker = DownloadTracker()
        let mine = UUID()
        let theirs = UUID()
        tracker.begin(id: mine, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: theirs, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: mine, destination: nil, at: start)
        tracker.finish(id: theirs, destination: nil, at: start)

        tracker.clear()

        XCTAssertEqual(tracker.state(now: afterDelay), .hidden)
        XCTAssertTrue(tracker.recentItems.isEmpty)
    }

    /// A running download of another service survives Clear, the same way a
    /// running download of the service on screen does.
    func testClearKeepsARunningDownloadOfAnotherService() {
        let tracker = DownloadTracker()
        let done = UUID()
        let running = UUID()
        tracker.begin(id: done, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: running, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: done, destination: nil, at: start)

        tracker.clear()

        XCTAssertEqual(tracker.recentItems.map(\.id), [running])
    }

    func testTheClearActionAppearsOnlyForAnEndedRecord() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        XCTAssertFalse(tracker.hasDismissibleItems)

        tracker.finish(id: id, destination: nil, at: start)

        XCTAssertTrue(tracker.hasDismissibleItems)
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
        guard let item = tracker.lastFinishedItem else {
            return XCTFail("The finished record is missing")
        }

        tracker.revealInFinder(item)

        XCTAssertEqual(tracker.state(now: afterDelay), .resting(count: 1, unseen: 1))
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

        XCTAssertEqual(tracker.state(now: afterDelay), .hidden)
        XCTAssertTrue(tracker.recentItems.isEmpty)
    }

    func testCancelAllStopsEveryService() {
        let tracker = DownloadTracker()
        let mine = CancelSpy()
        let theirs = CancelSpy()
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "a.zip", startedAt: start) { mine.cancel() }
        tracker.begin(id: UUID(), serviceID: otherServiceID, filename: "b.zip", startedAt: start) { theirs.cancel() }

        tracker.cancelAll()

        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(theirs.count, 1)
    }

    // MARK: - One list for every service

    /// The point of the change: one control reports the downloads of every
    /// service, the way a browser download center does.
    func testDownloadsOfTwoServicesShareOneControl() {
        let tracker = DownloadTracker()
        let mine = UUID()
        let theirs = UUID()
        tracker.begin(id: mine, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: theirs, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})

        tracker.updateProgress(id: mine, received: 1, expected: 2)
        tracker.updateProgress(id: theirs, received: 1, expected: 2)

        XCTAssertEqual(
            tracker.state(now: afterDelay),
            .active(fraction: 0.5, count: 2, unseen: 2)
        )
        XCTAssertEqual(tracker.recentItems.map(\.filename), ["b.zip", "a.zip"])
        XCTAssertEqual(tracker.activeItems.count, 2)
    }

    /// The tracker has no selected service, so nothing in it can follow one.
    /// This test states the exit condition of the change: the answer is the same
    /// whichever service the window shows, because no query takes a service.
    func testTheStateAndTheListDoNotFollowAnySelection() {
        let tracker = DownloadTracker()
        let mine = UUID()
        let theirs = UUID()
        tracker.begin(id: mine, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: theirs, serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})
        tracker.finish(id: theirs, destination: nil, at: start)

        let state = tracker.state(now: afterDelay)
        let names = tracker.recentItems.map(\.filename)
        let unseen = tracker.unseenCount(now: afterDelay)

        // A second read after a switch of service reaches the same values: the
        // records are the only input.
        XCTAssertEqual(tracker.state(now: afterDelay), state)
        XCTAssertEqual(tracker.recentItems.map(\.filename), names)
        XCTAssertEqual(tracker.unseenCount(now: afterDelay), unseen)
        XCTAssertEqual(state.recordCount, 2)
        XCTAssertEqual(names.count, 2)
    }

    func testADownloadWithoutAServiceStaysInTheList() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: nil, filename: "a.zip", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.state(now: afterDelay), .active(fraction: nil, count: 1, unseen: 1))
        XCTAssertNil(tracker.recentItems.first?.serviceID)
        XCTAssertNil(tracker.recentItems.first?.serviceLabel)
    }

    // MARK: - The source on each record

    func testARecordCapturesTheNameOfItsService() {
        let tracker = DownloadTracker()
        tracker.serviceLabelProvider = { [serviceID, otherServiceID] id in
            switch id {
            case serviceID: return "Gmail"
            case otherServiceID: return "Calendar"
            default: return nil
            }
        }

        tracker.begin(id: UUID(), serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: UUID(), serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})

        XCTAssertEqual(
            tracker.recentItems.map(\.serviceLabel),
            ["Calendar", "Gmail"]
        )
    }

    /// The name is a snapshot, so a rename or a deletion cannot leave a record
    /// without a source. The row of a removed service keeps that name and loses
    /// only its icon.
    func testTheCapturedNameSurvivesTheRemovalOfItsService() {
        let tracker = DownloadTracker()
        tracker.serviceLabelProvider = { _ in "Gmail" }
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        // The user deletes the service. Nothing answers for it any more.
        tracker.serviceLabelProvider = { _ in nil }
        tracker.updateProgress(id: id, received: 1, expected: 2)
        tracker.finish(id: id, destination: nil, at: afterDelay)

        guard let item = tracker.recentItems.first else {
            return XCTFail("The record of the removed service is missing")
        }
        XCTAssertEqual(item.serviceLabel, "Gmail")
        XCTAssertEqual(item.serviceID, serviceID)
        XCTAssertEqual(
            DownloadSource.resolve(
                serviceID: item.serviceID,
                label: item.serviceLabel,
                serviceExists: false
            ),
            .removedService(label: "Gmail")
        )
    }

    /// Removing a service leaves its record in place, and every list action still
    /// answers for it.
    func testARecordOfARemovedServiceStaysUsable() {
        let tracker = DownloadTracker()
        tracker.serviceLabelProvider = { _ in "Gmail" }
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.finish(id: id, destination: nil, at: start)

        tracker.serviceLabelProvider = nil

        XCTAssertEqual(tracker.state(now: afterDelay), .resting(count: 1, unseen: 1))
        XCTAssertTrue(tracker.hasDismissibleItems)
        tracker.acknowledgeAll()
        XCTAssertEqual(tracker.unseenCount(now: afterDelay), 0)
        tracker.dismiss(id: id)
        XCTAssertTrue(tracker.recentItems.isEmpty)
    }

    /// A record without a service captures no name, so its row shows no source.
    func testADownloadWithoutAServiceCapturesNoName() {
        let tracker = DownloadTracker()
        tracker.serviceLabelProvider = { _ in "Gmail" }

        tracker.begin(id: UUID(), serviceID: nil, filename: "a.zip", startedAt: start, cancel: {})

        XCTAssertNil(tracker.recentItems.first?.serviceLabel)
        XCTAssertEqual(
            DownloadSource.resolve(
                serviceID: nil,
                label: tracker.recentItems.first?.serviceLabel,
                serviceExists: false
            ),
            .unattributed
        )
    }

    // MARK: - Hibernation

    /// A download handler keeps itself alive after its service hibernates, so the
    /// transfer continues. The global list therefore keeps reporting its
    /// progress, even though nothing shows that service's page.
    func testAHibernatedServiceKeepsReportingItsProgress() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: otherServiceID, filename: "big.zip", startedAt: start, cancel: {})

        // The service hibernates: its web view and coordinator are gone, and the
        // handler reports the rest of the transfer on its own.
        tracker.updateProgress(id: id, received: 30, expected: 100)
        XCTAssertEqual(
            tracker.state(now: afterDelay),
            .active(fraction: 0.3, count: 1, unseen: 1)
        )

        tracker.updateProgress(id: id, received: 100, expected: 100)
        tracker.finish(
            id: id,
            destination: URL(fileURLWithPath: "/Users/test/Downloads/big.zip"),
            at: afterDelay
        )

        XCTAssertEqual(tracker.state(now: afterDelay), .resting(count: 1, unseen: 1))
        XCTAssertEqual(tracker.lastFinishedItem?.filename, "big.zip")
    }

    /// A capacity eviction removes the web view of a service that the user is not
    /// reading. Its download is not part of that eviction.
    func testAnEvictedServiceKeepsItsRecordBesideALiveDownload() {
        let tracker = DownloadTracker()
        let evicted = UUID()
        let live = UUID()
        tracker.begin(id: evicted, serviceID: otherServiceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: live, serviceID: serviceID, filename: "b.zip", startedAt: start, cancel: {})

        tracker.updateProgress(id: evicted, received: 50, expected: 100)
        tracker.updateProgress(id: live, received: 50, expected: 100)

        XCTAssertEqual(
            tracker.state(now: afterDelay),
            .active(fraction: 0.5, count: 2, unseen: 2)
        )
        XCTAssertEqual(tracker.recentItems.map(\.filename), ["b.zip", "a.zip"])
    }

    func testTheListShowsTheNewestDownloadFirst() {
        let tracker = DownloadTracker()
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "first.zip", startedAt: start, cancel: {})
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "second.zip", startedAt: start, cancel: {})

        XCTAssertEqual(
            tracker.recentItems.map(\.filename),
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

        XCTAssertEqual(tracker.state(now: afterDelay), .hidden)
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
        XCTAssertEqual(tracker.activeItems.map(\.id), [running])
    }

    // MARK: - The start signal

    func testAStartedDownloadReportsOneStart() {
        let tracker = DownloadTracker()

        tracker.begin(
            id: UUID(),
            serviceID: serviceID,
            filename: "report.pdf",
            startedAt: start,
            cancel: {}
        )

        let event = tracker.lastStart
        XCTAssertEqual(event?.sequence, 1)
        XCTAssertEqual(event?.serviceID, serviceID)
        XCTAssertEqual(event?.filename, "report.pdf")
        XCTAssertEqual(event?.startedAt, start)
    }

    func testANewTrackerReportsNoStart() {
        XCTAssertNil(DownloadTracker().lastStart)
    }

    func testEachNewDownloadReportsItsOwnStart() {
        let tracker = DownloadTracker()

        tracker.begin(id: UUID(), serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        tracker.begin(id: UUID(), serviceID: otherServiceID, filename: "b.zip", startedAt: start, cancel: {})

        XCTAssertEqual(tracker.lastStart?.sequence, 2)
        XCTAssertEqual(tracker.lastStart?.filename, "b.zip")
        XCTAssertEqual(tracker.lastStart?.serviceID, otherServiceID)
    }

    /// Everything that happens to a download after it starts leaves the signal
    /// alone, so the header animates one time for each transfer.
    func testProgressAndResultsReportNoNewStart() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})
        let afterBegin = tracker.lastStart

        tracker.updateProgress(id: id, received: 100, expected: 400)
        tracker.setDestination(id: id, destination: URL(fileURLWithPath: "/tmp/a.zip"))
        tracker.updateProgress(id: id, received: 400, expected: 400)
        tracker.finish(id: id, destination: URL(fileURLWithPath: "/tmp/a.zip"), at: afterDelay)
        tracker.acknowledgeAll()
        tracker.dismiss(id: id)

        XCTAssertEqual(tracker.lastStart, afterBegin)
        XCTAssertEqual(tracker.lastStart?.sequence, 1)
    }

    func testAFailureReportsNoNewStart() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.fail(id: id, at: afterDelay)

        XCTAssertEqual(tracker.lastStart?.sequence, 1)
    }

    /// Reading the list is not a start. This is what happens when the user
    /// switches to another service while a download runs: the global list keeps
    /// its records, and none of its queries reports a new download.
    func testReadingAnExistingDownloadReportsNoNewStart() {
        let tracker = DownloadTracker()
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        _ = tracker.state(now: afterDelay)
        _ = tracker.recentItems
        _ = tracker.activeItems
        _ = tracker.lastFinishedItem
        _ = tracker.hasDismissibleItems
        _ = tracker.unseenCount(now: afterDelay)

        XCTAssertEqual(tracker.lastStart?.sequence, 1)
    }

    func testAStoppedDownloadReportsNoNewStart() {
        let tracker = DownloadTracker()
        let id = UUID()
        tracker.begin(id: id, serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.markCancelled(id: id)

        XCTAssertEqual(tracker.lastStart?.sequence, 1)
    }

    func testStopDropsTheStartSignal() {
        let tracker = DownloadTracker()
        tracker.begin(id: UUID(), serviceID: serviceID, filename: "a.zip", startedAt: start, cancel: {})

        tracker.stop()

        XCTAssertNil(tracker.lastStart)
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
