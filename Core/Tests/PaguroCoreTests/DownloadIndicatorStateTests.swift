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

    @Test("A start announcement names its file")
    func startAnnouncementNamesItsFile() {
        #expect(
            DownloadIndicatorState.startAnnouncement(filename: "report.pdf")
                == "Download started: report.pdf"
        )
    }

    @Test("A start announcement without a name still reports the start")
    func startAnnouncementWithoutANameStillReportsTheStart() {
        #expect(DownloadIndicatorState.startAnnouncement(filename: "") == "Download started")
        #expect(DownloadIndicatorState.startAnnouncement(filename: "  ") == "Download started")
    }

    // MARK: - The mark that reports a start

    @Test("One flight lasts between half a second and seven tenths")
    func oneFlightLastsInsideItsBudget() {
        let total = DownloadIndicatorMotion.flightTotal

        #expect(total == .milliseconds(560))
        #expect(total >= .milliseconds(500))
        #expect(total <= .milliseconds(700))
    }

    @Test("A flight lands after the control has earned its place")
    func aFlightLandsAfterTheControlEntered() {
        // The first download of a service shows no control until the ring
        // delay passes. A landing before that would reach an empty header.
        #expect(DownloadIndicatorMotion.flightTotal >= DownloadIndicatorState.ringDelay)
    }

    @Test("The fade at the end stays inside the travel")
    func theFadeAtTheEndStaysInsideTheTravel() {
        #expect(DownloadIndicatorMotion.flightExit < DownloadIndicatorMotion.flightTravel)
    }

    @Test("The mark grows into its start place and shrinks into the control")
    func theMarkGrowsThenShrinks() {
        #expect(DownloadIndicatorMotion.flightEntryScale < 1)
        #expect(DownloadIndicatorMotion.flightArrivalScale < 1)
        #expect(DownloadIndicatorMotion.flightArrivalScale
            < DownloadIndicatorMotion.flightEntryScale)
    }

    @Test("The mark starts above the middle of the web content")
    func theMarkStartsAboveTheMiddleOfTheContent() {
        #expect(DownloadIndicatorMotion.flightStartFraction > 0)
        #expect(DownloadIndicatorMotion.flightStartFraction < 0.5)
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion replaces the travel with a fade at the control")
    func reduceMotionReplacesTheTravel() {
        let cue = DownloadStartCue.resolve(reduceMotion: true)

        #expect(cue == .destinationFade)
        #expect(cue.hasTravel == false)
        #expect(cue.duration == DownloadIndicatorMotion.flightFade)
        #expect(cue.duration < DownloadIndicatorMotion.flightTotal)
    }

    @Test("Full motion sends the mark on its travel")
    func fullMotionSendsTheMarkOnItsTravel() {
        let cue = DownloadStartCue.resolve(reduceMotion: false)

        #expect(cue == .flight)
        #expect(cue.hasTravel)
        #expect(cue.duration == DownloadIndicatorMotion.flightTotal)
    }

    // MARK: - The cue for one global control

    private static let gmailID = UUID()
    private static let calendarID = UUID()

    @Test("A start in the service on screen keeps the travel")
    func aStartInTheServiceOnScreenKeepsTheTravel() {
        let cue = DownloadStartCue.resolve(
            eventServiceID: Self.gmailID,
            selectedServiceID: Self.gmailID,
            reduceMotion: false,
            contentIsOnScreen: true
        )

        #expect(cue == .flight)
    }

    /// The control is global, so the start has to reach the header. A mark from
    /// the page on screen would name the wrong source, so the cue happens at the
    /// control instead.
    @Test("A start in another service uses the cue at the control")
    func aStartInAnotherServiceUsesTheCueAtTheControl() {
        let cue = DownloadStartCue.resolve(
            eventServiceID: Self.calendarID,
            selectedServiceID: Self.gmailID,
            reduceMotion: false,
            contentIsOnScreen: true
        )

        #expect(cue == .destinationFade)
        #expect(cue?.hasTravel == false)
    }

    @Test("A download without a service keeps the travel")
    func aDownloadWithoutAServiceKeepsTheTravel() {
        let cue = DownloadStartCue.resolve(
            eventServiceID: nil,
            selectedServiceID: Self.gmailID,
            reduceMotion: false,
            contentIsOnScreen: true
        )

        #expect(cue == .flight)
    }

    @Test("Reduce Motion drops the travel for every service")
    func reduceMotionDropsTheTravelForEveryService() {
        for eventServiceID in [Self.gmailID, Self.calendarID, nil] {
            let cue = DownloadStartCue.resolve(
                eventServiceID: eventServiceID,
                selectedServiceID: Self.gmailID,
                reduceMotion: true,
                contentIsOnScreen: true
            )

            #expect(cue == .destinationFade)
        }
    }

    /// The window shows no service page, so a mark has no place to leave from.
    @Test("A window without web content produces no cue")
    func aWindowWithoutWebContentProducesNoCue() {
        for reduceMotion in [true, false] {
            let cue = DownloadStartCue.resolve(
                eventServiceID: Self.gmailID,
                selectedServiceID: Self.gmailID,
                reduceMotion: reduceMotion,
                contentIsOnScreen: false
            )

            #expect(cue == nil)
        }
    }

    // MARK: - The source on one row

    @Test("A live service names itself and draws its icon")
    func aLiveServiceNamesItselfAndDrawsItsIcon() {
        let source = DownloadSource.resolve(
            serviceID: Self.gmailID,
            label: "Gmail",
            serviceExists: true
        )

        #expect(source == .service(label: "Gmail"))
        #expect(source.label == "Gmail")
        #expect(source.drawsServiceIcon)
        #expect(source.spokenPhrase == "from Gmail")
    }

    /// The record keeps the name it captured, so the row stays readable after
    /// the service leaves the workspace.
    @Test("A removed service keeps its recorded name and loses its icon")
    func aRemovedServiceKeepsItsRecordedName() {
        let source = DownloadSource.resolve(
            serviceID: Self.gmailID,
            label: "Gmail",
            serviceExists: false
        )

        #expect(source == .removedService(label: "Gmail"))
        #expect(source.label == "Gmail")
        #expect(source.drawsServiceIcon == false)
        #expect(source.spokenPhrase == "from Gmail")
    }

    @Test("A download without a service shows no source")
    func aDownloadWithoutAServiceShowsNoSource() {
        let source = DownloadSource.resolve(
            serviceID: nil,
            label: "Gmail",
            serviceExists: true
        )

        #expect(source == .unattributed)
        #expect(source.label == nil)
        #expect(source.drawsServiceIcon == false)
        #expect(source.spokenPhrase == nil)
    }

    @Test("A blank recorded name shows no source", arguments: [nil, "", "   "])
    func aBlankRecordedNameShowsNoSource(label: String?) {
        let source = DownloadSource.resolve(
            serviceID: Self.gmailID,
            label: label,
            serviceExists: false
        )

        #expect(source == .unattributed)
    }

    // MARK: - Concurrent starts

    /// A fixed moment. Every planner test measures from it, so no test reads a
    /// clock.
    private static let firstStart = Date(timeIntervalSince1970: 3_000_000)

    private static func moment(_ seconds: Double) -> Date {
        firstStart.addingTimeInterval(seconds)
    }

    @Test("The first start sends one mark at once")
    func theFirstStartSendsOneMarkAtOnce() {
        var planner = DownloadFlightPlanner()

        #expect(planner.plan(startedAt: Self.firstStart) == .launch(flightID: 1, delay: .zero))
        #expect(planner.flightCount == 1)
    }

    @Test("Starts inside the group window share one mark")
    func startsInsideTheWindowShareOneMark() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)

        #expect(planner.plan(startedAt: Self.moment(0.1)) == .joinsFlight(flightID: 1))
        #expect(planner.plan(startedAt: Self.moment(0.29)) == .joinsFlight(flightID: 1))
        #expect(planner.flightCount == 1)
        #expect(planner.count(ofFlight: 1) == 3)
    }

    @Test("Ten downloads at one moment send one mark")
    func tenDownloadsAtOneMomentSendOneMark() {
        var planner = DownloadFlightPlanner()

        for index in 0..<10 {
            _ = planner.plan(startedAt: Self.moment(Double(index) * 0.01))
        }

        #expect(planner.flightCount == 1)
        #expect(planner.count(ofFlight: 1) == 10)
    }

    @Test("A start after the window waits for the minimum gap")
    func aStartAfterTheWindowWaitsForTheMinimumGap() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)

        // 0.35 seconds is outside the group window and inside the gap, so the
        // second mark leaves 0.4 seconds after the first one.
        #expect(
            planner.plan(startedAt: Self.moment(0.35))
                == .launch(flightID: 2, delay: .milliseconds(50))
        )
        #expect(planner.flightCount == 2)
    }

    @Test("A later start needs no delay")
    func aLaterStartNeedsNoDelay() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)

        #expect(planner.plan(startedAt: Self.moment(0.9)) == .launch(flightID: 2, delay: .zero))
    }

    @Test("A mark that reached the control leaves the count")
    func aMarkThatReachedTheControlLeavesTheCount() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)

        planner.forget(flightID: 1)

        #expect(planner.flightCount == 0)
        #expect(planner.count(ofFlight: 1) == nil)
        // The next start opens a group of its own, because no mark remains.
        #expect(planner.plan(startedAt: Self.moment(0.1)) == .launch(flightID: 2, delay: .zero))
    }

    @Test("The limit stops a fourth mark and the header keeps the count")
    func theLimitStopsAFourthMark() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)
        _ = planner.plan(startedAt: Self.moment(0.5))
        _ = planner.plan(startedAt: Self.moment(1.0))

        #expect(planner.flightCount == DownloadFlightPlanner.maximumFlights)
        #expect(planner.plan(startedAt: Self.moment(1.5)) == .capped)
        #expect(planner.flightCount == DownloadFlightPlanner.maximumFlights)
    }

    @Test("A mark that no caller reported leaves after its stale life")
    func aStaleMarkLeavesTheCount() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)

        #expect(planner.plan(startedAt: Self.moment(2.0)) == .launch(flightID: 2, delay: .zero))
        #expect(planner.flightCount == 1)
    }

    @Test("Forgetting every mark empties the planner")
    func forgettingEveryMarkEmptiesThePlanner() {
        var planner = DownloadFlightPlanner()
        _ = planner.plan(startedAt: Self.firstStart)
        _ = planner.plan(startedAt: Self.moment(0.5))

        planner.forgetAll()

        #expect(planner.flightCount == 0)
    }
}
