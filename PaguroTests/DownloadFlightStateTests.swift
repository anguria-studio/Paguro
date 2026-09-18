import XCTest
import PaguroCore
@testable import Paguro

/// Covers the marks that report a download start.
///
/// No test builds a view. The state answers a start event with a list of marks
/// and an arrival count, so the rule is readable without a window. The travel
/// itself belongs to `DownloadStartFlightOverlay`, and the numbers behind it
/// belong to `DownloadIndicatorMotion` in `PaguroCore`.
@MainActor
final class DownloadFlightStateTests: XCTestCase {
    private let serviceID = UUID()

    /// A fixed clock, so no test waits for a real moment.
    private let start = Date(timeIntervalSince1970: 4_000_000)

    private func event(
        sequence: Int,
        filename: String = "report.pdf",
        at offset: Double = 0
    ) -> DownloadTracker.StartEvent {
        DownloadTracker.StartEvent(
            sequence: sequence,
            serviceID: serviceID,
            filename: filename,
            startedAt: start.addingTimeInterval(offset)
        )
    }

    func testAStartSendsOneMark() {
        let state = DownloadFlightState()

        state.start(event(sequence: 1), reduceMotion: false, at: start)

        XCTAssertEqual(state.flights.count, 1)
        XCTAssertEqual(state.flights.first?.delay, .zero)
        XCTAssertEqual(state.arrivalTick, 0)
    }

    func testAMarkThatLandsReportsItsArrivalAndLeaves() {
        let state = DownloadFlightState()
        state.start(event(sequence: 1), reduceMotion: false, at: start)
        guard let flight = state.flights.first else { return XCTFail("No mark left") }

        state.arrive(flightID: flight.id)

        XCTAssertTrue(state.flights.isEmpty)
        XCTAssertEqual(state.arrivalTick, 1)
    }

    func testAnArrivalOfAnUnknownMarkChangesNothing() {
        let state = DownloadFlightState()

        state.arrive(flightID: 99)

        XCTAssertEqual(state.arrivalTick, 0)
    }

    /// The same start reported twice must not send a second mark. The sequence
    /// grows for a real new download only.
    func testTheSameStartSendsOneMarkOnly() {
        let state = DownloadFlightState()
        let repeated = event(sequence: 1)

        state.start(repeated, reduceMotion: false, at: start)
        state.start(repeated, reduceMotion: false, at: start.addingTimeInterval(1))

        XCTAssertEqual(state.flights.count, 1)
    }

    func testStartsInOneMomentShareOneMark() {
        let state = DownloadFlightState()

        for index in 1...10 {
            state.start(
                event(sequence: index, filename: "file-\(index).zip", at: Double(index) * 0.01),
                reduceMotion: false,
                at: start.addingTimeInterval(Double(index) * 0.01)
            )
        }

        XCTAssertEqual(state.flights.count, 1)
    }

    func testALaterStartSendsItsOwnMark() {
        let state = DownloadFlightState()
        state.start(event(sequence: 1), reduceMotion: false, at: start)

        state.start(
            event(sequence: 2, at: 0.9),
            reduceMotion: false,
            at: start.addingTimeInterval(0.9)
        )

        XCTAssertEqual(state.flights.count, 2)
    }

    /// Reduce Motion has no travel. The cue happens at the control, so the state
    /// sends no mark and reports the arrival at once.
    func testReduceMotionSendsNoMarkAndReportsTheArrival() {
        let state = DownloadFlightState()

        state.start(event(sequence: 1), reduceMotion: true, at: start)

        XCTAssertTrue(state.flights.isEmpty)
        XCTAssertEqual(state.arrivalTick, 1)
    }

    func testReduceMotionGroupsStartsInOneMoment() {
        let state = DownloadFlightState()

        for index in 1...5 {
            state.start(
                event(sequence: index, at: Double(index) * 0.01),
                reduceMotion: true,
                at: start.addingTimeInterval(Double(index) * 0.01)
            )
        }

        // One cue for the group, not one for each download. The header badge
        // still counts all five.
        XCTAssertEqual(state.arrivalTick, 1)
    }

    func testStopDropsEveryMark() {
        let state = DownloadFlightState()
        state.start(event(sequence: 1), reduceMotion: false, at: start)

        state.stop()

        XCTAssertTrue(state.flights.isEmpty)
    }
}
