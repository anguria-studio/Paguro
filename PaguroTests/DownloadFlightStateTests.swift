import XCTest
import PaguroCore
@testable import Paguro

/// Covers the marks that report a download start.
///
/// No test builds a view. The state answers a start event and a cue with a list
/// of marks and an arrival count, so the rule is readable without a window.
/// `DownloadStartCue.resolve` in `PaguroCore` chooses the cue, and
/// `DownloadStartFlightOverlay` gives it the values it needs. The travel itself
/// belongs to that overlay, and the numbers behind it belong to
/// `DownloadIndicatorMotion`.
@MainActor
final class DownloadFlightStateTests: XCTestCase {
    private let serviceID = UUID()
    private let otherServiceID = UUID()

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

        state.start(event(sequence: 1), cue: .flight, at: start)

        XCTAssertEqual(state.flights.count, 1)
        XCTAssertEqual(state.flights.first?.delay, .zero)
        XCTAssertEqual(state.arrivalTick, 0)
    }

    func testAMarkThatLandsReportsItsArrivalAndLeaves() {
        let state = DownloadFlightState()
        state.start(event(sequence: 1), cue: .flight, at: start)
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

        state.start(repeated, cue: .flight, at: start)
        state.start(repeated, cue: .flight, at: start.addingTimeInterval(1))

        XCTAssertEqual(state.flights.count, 1)
    }

    func testStartsInOneMomentShareOneMark() {
        let state = DownloadFlightState()

        for index in 1...10 {
            state.start(
                event(sequence: index, filename: "file-\(index).zip", at: Double(index) * 0.01),
                cue: .flight,
                at: start.addingTimeInterval(Double(index) * 0.01)
            )
        }

        XCTAssertEqual(state.flights.count, 1)
    }

    func testALaterStartSendsItsOwnMark() {
        let state = DownloadFlightState()
        state.start(event(sequence: 1), cue: .flight, at: start)

        state.start(
            event(sequence: 2, at: 0.9),
            cue: .flight,
            at: start.addingTimeInterval(0.9)
        )

        XCTAssertEqual(state.flights.count, 2)
    }

    /// The destination cue has no travel. It happens at the control, so the
    /// state sends no mark and reports the arrival at once. Reduce Motion and a
    /// start in another service both use it.
    func testTheDestinationCueSendsNoMarkAndReportsTheArrival() {
        let state = DownloadFlightState()

        state.start(event(sequence: 1), cue: .destinationFade, at: start)

        XCTAssertTrue(state.flights.isEmpty)
        XCTAssertEqual(state.arrivalTick, 1)
    }

    func testTheDestinationCueGroupsStartsInOneMoment() {
        let state = DownloadFlightState()

        for index in 1...5 {
            state.start(
                event(sequence: index, at: Double(index) * 0.01),
                cue: .destinationFade,
                at: start.addingTimeInterval(Double(index) * 0.01)
            )
        }

        // One cue for the group, not one for each download. The header badge
        // still counts all five.
        XCTAssertEqual(state.arrivalTick, 1)
    }

    // MARK: - The cue for one global control

    /// The control counts every service, so a start in a service the window does
    /// not show still reaches it. A mark would rise out of the wrong page, so the
    /// rule answers with the cue at the control and the state sends no mark.
    func testAStartInAnotherServiceReachesTheControlWithoutAMark() {
        let state = DownloadFlightState()
        let event = DownloadTracker.StartEvent(
            sequence: 1,
            serviceID: otherServiceID,
            filename: "b.zip",
            startedAt: start
        )
        guard let cue = DownloadStartCue.resolve(
            eventServiceID: event.serviceID,
            selectedServiceID: serviceID,
            reduceMotion: false,
            contentIsOnScreen: true
        ) else { return XCTFail("The start reported nothing") }

        state.start(event, cue: cue, at: start)

        XCTAssertEqual(cue, .destinationFade)
        XCTAssertTrue(state.flights.isEmpty)
        XCTAssertEqual(state.arrivalTick, 1)
    }

    /// A start in the service on screen keeps the travel, so the change costs
    /// the common case nothing.
    func testAStartInTheServiceOnScreenStillSendsAMark() {
        let state = DownloadFlightState()
        guard let cue = DownloadStartCue.resolve(
            eventServiceID: serviceID,
            selectedServiceID: serviceID,
            reduceMotion: false,
            contentIsOnScreen: true
        ) else { return XCTFail("The start reported nothing") }

        state.start(event(sequence: 1), cue: cue, at: start)

        XCTAssertEqual(cue, .flight)
        XCTAssertEqual(state.flights.count, 1)
        XCTAssertEqual(state.arrivalTick, 0)
    }

    /// The window shows no service page, so the start reports nothing and never
    /// reaches the state.
    func testAWindowWithoutWebContentSendsNothing() {
        let state = DownloadFlightState()
        let cue = DownloadStartCue.resolve(
            eventServiceID: serviceID,
            selectedServiceID: serviceID,
            reduceMotion: false,
            contentIsOnScreen: false
        )

        XCTAssertNil(cue)
        XCTAssertTrue(state.flights.isEmpty)
        XCTAssertEqual(state.arrivalTick, 0)
    }

    // MARK: - Session scope

    func testStopDropsEveryMark() {
        let state = DownloadFlightState()
        state.start(event(sequence: 1), cue: .flight, at: start)

        state.stop()

        XCTAssertTrue(state.flights.isEmpty)
    }
}
