import XCTest
@testable import PaguroCore

final class CapacityEvictionNoticeTests: XCTestCase {
    func testTheNoticeAppearsOnceForEachAppRun() {
        XCTAssertTrue(CapacityEvictionNotice.shouldAnnounce(hasAnnouncedThisRun: false))
        XCTAssertFalse(CapacityEvictionNotice.shouldAnnounce(hasAnnouncedThisRun: true))
    }

    func testTheMessageNamesTheServiceAndTheKeepLoadedControl() {
        let message = CapacityEvictionNotice.message(serviceName: "Notion")

        XCTAssertTrue(message.contains("Notion"), message)
        XCTAssertTrue(message.contains("\"Keep Loaded\""), message)
        XCTAssertTrue(message.contains("memory"), message)
    }

    func testTheMessageStatesThePoolLimit() {
        let message = CapacityEvictionNotice.message(serviceName: "Notion")

        XCTAssertTrue(
            message.contains("\(WebViewPoolCapacity.maxLoaded)"),
            "the notice must state the number of services that stay loaded: \(message)"
        )
    }

    func testTheSettingsSentenceStatesThePoolLimit() {
        let sentence = CapacityEvictionNotice.settingsSummary

        XCTAssertTrue(
            sentence.contains("\(WebViewPoolCapacity.maxLoaded)"),
            sentence
        )
        XCTAssertTrue(sentence.contains("idle hibernation is off"), sentence)
    }

    func testTheCardTitleCarriesText() {
        XCTAssertFalse(CapacityEvictionNotice.title.isEmpty)
    }

    func testAnEmptyLabelUsesTheFallbackName() {
        XCTAssertEqual(
            CapacityEvictionNotice.message(serviceName: "   \n "),
            CapacityEvictionNotice.message(serviceName: "")
        )
        XCTAssertTrue(
            CapacityEvictionNotice.message(serviceName: "")
                .contains(CapacityEvictionNotice.fallbackServiceName)
        )
    }

    func testALongLabelIsCutAndKeepsTheExplanation() {
        let longName = String(repeating: "A", count: 400)

        let message = CapacityEvictionNotice.message(serviceName: longName)

        XCTAssertFalse(message.contains(longName), "the complete label must not reach the notice")
        XCTAssertTrue(
            message.contains(String(repeating: "A", count: CapacityEvictionNotice.maximumServiceNameLength) + "…"),
            message
        )
        XCTAssertTrue(message.contains("\"Keep Loaded\""), message)
        XCTAssertLessThan(message.count, 200)
    }

    func testTheSurroundingLabelSpaceDoesNotReachTheNotice() {
        XCTAssertEqual(
            CapacityEvictionNotice.message(serviceName: "  Slack  "),
            CapacityEvictionNotice.message(serviceName: "Slack")
        )
    }

    func testThePoolCapacityStaysAPositiveNumber() {
        XCTAssertGreaterThan(WebViewPoolCapacity.maxLoaded, 1)
    }
}
