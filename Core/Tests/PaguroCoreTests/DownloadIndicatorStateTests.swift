import Foundation
import Testing
@testable import PaguroCore

@Suite("Download indicator")
struct DownloadIndicatorStateTests {

    // MARK: - Totals

    @Test("An active download without an expected size reports no fraction")
    func fractionIsNilWithoutAnExpectedSize() {
        let totals = DownloadProgressTotals(
            activeCount: 1,
            receivedBytes: 500,
            expectedBytes: 0
        )

        #expect(totals.fraction == nil)
    }

    @Test("The fraction combines every active download")
    func fractionCombinesEveryActiveDownload() {
        let totals = DownloadProgressTotals(
            activeCount: 2,
            receivedBytes: 300,
            expectedBytes: 1200
        )

        #expect(totals.fraction == 0.25)
    }

    @Test("A download larger than its expected size clamps to one")
    func fractionClampsAnOversizedDownload() {
        let totals = DownloadProgressTotals(
            activeCount: 1,
            receivedBytes: 2000,
            expectedBytes: 1000
        )

        #expect(totals.fraction == 1)
    }

    // MARK: - Visibility rules

    @Test("The indicator hides without a record")
    func stateIsHiddenWithoutARecord() {
        let state = DownloadIndicatorState.resolve(
            totals: .none,
            recordCount: 0,
            unseenCount: 0,
            failedCount: 0,
            longestActiveElapsed: nil
        )

        #expect(state == .hidden)
        #expect(state.isVisible == false)
    }

    @Test("An active download reports its fraction")
    func activeDownloadReportsItsFraction() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(
                activeCount: 1,
                receivedBytes: 250,
                expectedBytes: 1000
            ),
            recordCount: 1,
            unseenCount: 1,
            failedCount: 0,
            longestActiveElapsed: .seconds(1)
        )

        #expect(state == .active(fraction: 0.25, count: 1, unseen: 1))
        #expect(state.ringFraction == 0.25)
        #expect(state.showsRing)
        #expect(state.isVisible)
    }

    @Test("An active download of unknown size reports no fraction")
    func activeDownloadWithoutASizeReportsNoFraction() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(
                activeCount: 1,
                receivedBytes: 250,
                expectedBytes: -1
            ),
            recordCount: 1,
            unseenCount: 1,
            failedCount: 0,
            longestActiveElapsed: .seconds(1)
        )

        #expect(state == .active(fraction: nil, count: 1, unseen: 1))
        #expect(state.ringFraction == nil)
        #expect(state.showsRing)
    }

    @Test("A finished record keeps the indicator visible and at rest")
    func aFinishedRecordRests() {
        let state = DownloadIndicatorState.resolve(
            totals: .none,
            recordCount: 1,
            unseenCount: 1,
            failedCount: 0,
            longestActiveElapsed: nil
        )

        #expect(state == .resting(count: 1, unseen: 1))
        #expect(state.isVisible)
        #expect(state.showsRing == false)
        #expect(state.glyph == .downloadMark)
    }

    @Test("Several finished records stay visible together")
    func severalFinishedRecordsStayVisible() {
        let state = DownloadIndicatorState.resolve(
            totals: .none,
            recordCount: 4,
            unseenCount: 4,
            failedCount: 0,
            longestActiveElapsed: nil
        )

        #expect(state == .resting(count: 4, unseen: 4))
    }

    @Test("A failed record shows the warning symbol")
    func aFailedRecordShowsTheWarningSymbol() {
        let state = DownloadIndicatorState.resolve(
            totals: .none,
            recordCount: 3,
            unseenCount: 3,
            failedCount: 1,
            longestActiveElapsed: nil
        )

        #expect(state == .failed(count: 3, failedCount: 1, unseen: 3))
        #expect(state.glyph == .systemSymbol(name: "exclamationmark.circle"))
    }

    @Test("A running download wins over a failed record")
    func aRunningDownloadWinsOverAFailedRecord() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(
                activeCount: 1,
                receivedBytes: 1,
                expectedBytes: 2
            ),
            recordCount: 2,
            unseenCount: 2,
            failedCount: 1,
            longestActiveElapsed: .seconds(1)
        )

        #expect(state == .active(fraction: 0.5, count: 2, unseen: 2))
        #expect(state.glyph == .downloadMark)
    }

    // MARK: - The ring delay

    /// One running download of a known size, with nothing else recorded.
    private func youngDownload(elapsed: Duration) -> DownloadIndicatorState {
        DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(
                activeCount: 1,
                receivedBytes: 100,
                expectedBytes: 400
            ),
            recordCount: 1,
            unseenCount: 1,
            failedCount: 0,
            longestActiveElapsed: elapsed
        )
    }

    @Test("A download shorter than the delay never shows a ring")
    func aFastDownloadNeverShowsARing() {
        #expect(youngDownload(elapsed: .milliseconds(200)) == .hidden)
        #expect(youngDownload(elapsed: .milliseconds(499)) == .hidden)
    }

    @Test("A download that finished fast goes straight to a resting count")
    func aFastDownloadRestsWithItsCount() {
        let state = DownloadIndicatorState.resolve(
            totals: .none,
            recordCount: 1,
            unseenCount: 1,
            failedCount: 0,
            longestActiveElapsed: nil
        )

        #expect(state == .resting(count: 1, unseen: 1))
        #expect(state.badgeText == "1")
        #expect(state.showsRing == false)
    }

    @Test("A download reaching the delay shows its ring")
    func aSlowDownloadCrossesTheThreshold() {
        #expect(
            youngDownload(elapsed: DownloadIndicatorState.ringDelay)
                == .active(fraction: 0.25, count: 1, unseen: 1)
        )
        #expect(youngDownload(elapsed: .seconds(3)) == .active(fraction: 0.25, count: 1, unseen: 1))
    }

    @Test("An unmeasured download counts as younger than the delay")
    func anUnmeasuredDownloadCountsAsYoung() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(activeCount: 1),
            recordCount: 1,
            unseenCount: 1,
            failedCount: 0,
            longestActiveElapsed: nil
        )

        #expect(state == .hidden)
    }

    @Test("A new download does not flash a ring over a finished record")
    func aNewDownloadKeepsAnExistingRestingMark() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(
                activeCount: 1,
                receivedBytes: 10,
                expectedBytes: 100
            ),
            recordCount: 3,
            unseenCount: 3,
            failedCount: 0,
            longestActiveElapsed: .milliseconds(100)
        )

        #expect(state == .resting(count: 3, unseen: 3))
        #expect(state.badgeText == "3")
    }

    @Test("A new download does not flash a ring over a failed record")
    func aNewDownloadKeepsAnExistingFailureMark() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(activeCount: 1),
            recordCount: 2,
            unseenCount: 2,
            failedCount: 1,
            longestActiveElapsed: .milliseconds(100)
        )

        #expect(state == .failed(count: 2, failedCount: 1, unseen: 2))
        #expect(state.glyph == .systemSymbol(name: "exclamationmark.circle"))
    }

    // MARK: - The count badge

    @Test("The badge counts the unseen downloads, not every row")
    func theBadgeCountsTheUnseenDownloads() {
        #expect(DownloadIndicatorState.hidden.badgeText == nil)
        #expect(DownloadIndicatorState.resting(count: 1, unseen: 1).badgeText == "1")
        #expect(DownloadIndicatorState.active(fraction: 0.5, count: 2, unseen: 2).badgeText == "2")
        #expect(DownloadIndicatorState.failed(count: 4, failedCount: 2, unseen: 4).badgeText == "4")
    }

    @Test("A seen record keeps its row and loses its badge")
    func aSeenRecordKeepsItsRow() {
        let state = DownloadIndicatorState.resolve(
            totals: .none,
            recordCount: 5,
            unseenCount: 0,
            failedCount: 0,
            longestActiveElapsed: nil
        )

        #expect(state == .resting(count: 5, unseen: 0))
        #expect(state.isVisible)
        #expect(state.badgeText == nil)
        #expect(state.recordCount == 5)
        #expect(state.unseenCount == 0)
        // The list still names every record, so the route to a file remains.
        #expect(state.accessibilityLabel == "5 downloads")
    }

    @Test("The record count and the unseen count are separate values")
    func theTwoCountsAreSeparate() {
        let state = DownloadIndicatorState.resolve(
            totals: DownloadProgressTotals(
                activeCount: 1,
                receivedBytes: 1,
                expectedBytes: 4
            ),
            recordCount: 7,
            unseenCount: 2,
            failedCount: 0,
            longestActiveElapsed: .seconds(1)
        )

        #expect(state == .active(fraction: 0.25, count: 7, unseen: 2))
        #expect(state.badgeText == "2")
        #expect(state.accessibilityLabel == "7 downloads, 25 percent complete")
    }

    @Test("The badge window is the documented value")
    func theBadgeWindowIsDocumented() {
        #expect(DownloadIndicatorState.badgeWindow == .seconds(12))
    }

    @Test("The count label caps at its largest printed value")
    func theCountLabelCaps() {
        #expect(DownloadCountLabel.text(for: 0) == nil)
        #expect(DownloadCountLabel.text(for: -2) == nil)
        #expect(DownloadCountLabel.text(for: 1) == "1")
        #expect(DownloadCountLabel.text(for: 9) == "9")
        #expect(DownloadCountLabel.text(for: 10) == "9+")
        #expect(DownloadCountLabel.text(for: 25) == "9+")
    }

    @Test("The record count matches the state it came from")
    func theRecordCountMatchesItsState() {
        #expect(DownloadIndicatorState.hidden.recordCount == 0)
        #expect(DownloadIndicatorState.hidden.unseenCount == 0)
        #expect(DownloadIndicatorState.resting(count: 6, unseen: 6).recordCount == 6)
        #expect(DownloadIndicatorState.active(fraction: nil, count: 2, unseen: 1).recordCount == 2)
        #expect(DownloadIndicatorState.failed(count: 3, failedCount: 1, unseen: 3).recordCount == 3)
    }

    // MARK: - Presentation

    @Test("Only a failed record leaves Paguro's own download mark")
    func onlyAFailedRecordLeavesTheDownloadMark() {
        #expect(DownloadIndicatorState.hidden.glyph == .downloadMark)
        #expect(DownloadIndicatorState.active(fraction: 0.5, count: 1, unseen: 1).glyph == .downloadMark)
        #expect(DownloadIndicatorState.resting(count: 2, unseen: 2).glyph == .downloadMark)
        #expect(
            DownloadIndicatorState.failed(count: 2, failedCount: 1, unseen: 2).glyph
                == .systemSymbol(name: "exclamationmark.circle")
        )
    }

    @Test("The accessibility label reports the completed percentage")
    func accessibilityLabelReportsTheCompletedPercentage() {
        #expect(
            DownloadIndicatorState.active(fraction: 0.421, count: 1, unseen: 1).accessibilityLabel
                == "1 download, 42 percent complete"
        )
        #expect(
            DownloadIndicatorState.active(fraction: nil, count: 3, unseen: 3).accessibilityLabel
                == "3 downloads, downloading"
        )
    }

    @Test("A resting control reports how many records it holds")
    func aRestingControlReportsItsRecordCount() {
        #expect(DownloadIndicatorState.resting(count: 1, unseen: 1).accessibilityLabel == "1 download")
        #expect(DownloadIndicatorState.resting(count: 5, unseen: 0).accessibilityLabel == "5 downloads")
        #expect(DownloadIndicatorState.resting(count: 5, unseen: 0).helpText == "5 downloads")
    }

    @Test("A failed control names the failed records")
    func aFailedControlNamesTheFailedRecords() {
        let state = DownloadIndicatorState.failed(count: 3, failedCount: 2, unseen: 0)

        #expect(state.accessibilityLabel == "3 downloads, 2 failed")
        #expect(state.helpText == "3 downloads, 2 failed")
    }

    @Test("The count text uses readable singular and plural forms")
    func countTextUsesReadableForms() {
        #expect(DownloadIndicatorState.countText(0) == "No downloads")
        #expect(DownloadIndicatorState.countText(1) == "1 download")
        #expect(DownloadIndicatorState.countText(9) == "9 downloads")
        #expect(DownloadIndicatorState.countText(-3) == "No downloads")
    }

    @Test("The percentage text clamps an invalid fraction")
    func percentTextClampsAnInvalidFraction() {
        #expect(DownloadIndicatorState.percentText(-0.5) == "0")
        #expect(DownloadIndicatorState.percentText(1.5) == "100")
        #expect(DownloadIndicatorState.percentText(0.005) == "1")
    }
}
