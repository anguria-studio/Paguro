import WebKit
import XCTest
@testable import Blatta

/// Covers the cadence of the active badge poll and the title kick that drives
/// it. The cadence rule is a value type, so these tests need no timer and no
/// real KVO delivery.
final class ActivePollScheduleTests: XCTestCase {
    func testTheFastCadencePollsOnEveryFifthTick() {
        var schedule = ActivePollSchedule()
        var polls = 0
        for _ in 0..<10 where schedule.advance(kicked: false) {
            polls += 1
        }
        XCTAssertEqual(polls, 2)
        XCTAssertEqual(schedule.interval, 5)
    }

    /// A quiet service slows down step by step. The cap keeps the badge of a
    /// service that the user watches no more than 15 seconds behind the page.
    func testAQuietServiceStepsDownToTheCapAndNoFurther() {
        var schedule = ActivePollSchedule()
        XCTAssertEqual(schedule.interval, 5)

        runUnchangedPolls(120, on: &schedule)
        XCTAssertEqual(schedule.interval, 10)

        runUnchangedPolls(120, on: &schedule)
        XCTAssertEqual(schedule.interval, 15)

        runUnchangedPolls(120, on: &schedule)
        XCTAssertEqual(schedule.interval, 15)
    }

    func testAChangedCountReturnsTheLoopToTheFastCadence() {
        var schedule = ActivePollSchedule()
        runUnchangedPolls(240, on: &schedule)
        XCTAssertEqual(schedule.interval, 15)

        schedule.recordResult(countChanged: true)
        XCTAssertEqual(schedule.interval, 5)
        XCTAssertEqual(schedule.unchangedCycles, 0)
    }

    /// A page-title change means the page state moved. The poll happens on the
    /// tick that carries the kick, and the back-off starts again — even when
    /// the count that the poll then reads is the same as before.
    func testATitleKickPollsAtOnceAndRestartsTheBackOff() {
        var schedule = ActivePollSchedule()
        runUnchangedPolls(240, on: &schedule)
        XCTAssertEqual(schedule.interval, 15)

        XCTAssertTrue(schedule.advance(kicked: true))
        XCTAssertEqual(schedule.interval, 5)
        XCTAssertEqual(schedule.unchangedCycles, 0)

        schedule.recordResult(countChanged: false)
        XCTAssertEqual(schedule.interval, 5)

        // The kick also restarts the count of ticks, so the poll after it comes
        // 5 ticks later instead of at the phase the slow cadence had reached.
        for tick in 1...4 {
            XCTAssertFalse(schedule.advance(kicked: false), "tick \(tick) must not poll")
        }
        XCTAssertTrue(schedule.advance(kicked: false))
    }

    /// The loop reads the kick on every tick, so a burst of title changes in
    /// one second costs one poll.
    @MainActor
    func testAKickStaysPendingUntilTheLoopConsumesItOnce() {
        let manager = NotificationManager(badgeManager: BadgeManager())
        let instanceID = UUID()

        XCTAssertFalse(manager.consumePollKick(for: instanceID))

        manager.kickPoll(for: instanceID)
        manager.kickPoll(for: instanceID)
        XCTAssertTrue(manager.consumePollKick(for: instanceID))
        XCTAssertFalse(manager.consumePollKick(for: instanceID))
    }

    /// Stopping a poll must end its kick with it. A kick that outlived the poll
    /// would make the next start of that service poll one tick too early.
    @MainActor
    func testStoppingAPollDropsItsPendingKick() {
        let manager = NotificationManager(badgeManager: BadgeManager())
        let webView = WKWebView(frame: .zero)
        let instanceID = UUID()

        manager.startPolling(
            for: instanceID,
            webView: webView,
            isMuted: { false },
            showBadge: { true },
            catalogEntry: nil,
            mode: .active
        )
        manager.kickPoll(for: instanceID)
        manager.stopPolling(for: instanceID)

        XCTAssertFalse(manager.consumePollKick(for: instanceID))
    }

    private func runUnchangedPolls(_ count: Int, on schedule: inout ActivePollSchedule) {
        var polls = 0
        while polls < count {
            if schedule.advance(kicked: false) {
                schedule.recordResult(countChanged: false)
                polls += 1
            }
        }
    }
}
