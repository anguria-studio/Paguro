import UserNotifications
import XCTest
@testable import Paguro

@MainActor
final class IslandNotificationSoundTests: XCTestCase {
    func testDefaultSoundHasNoVisualContentOrServiceData() throws {
        let center = RecordingIslandSoundCenter()
        let player = IslandNotificationSoundPlayer(center: center)
        player.play()
        let request = try XCTUnwrap(center.requests.first)

        XCTAssertEqual(request.content.sound, .default)
        XCTAssertTrue(request.content.title.isEmpty)
        XCTAssertTrue(request.content.subtitle.isEmpty)
        XCTAssertTrue(request.content.body.isEmpty)
        XCTAssertTrue(request.content.userInfo.isEmpty)
        XCTAssertTrue(request.content.attachments.isEmpty)
        XCTAssertTrue(request.content.categoryIdentifier.isEmpty)
        XCTAssertNil(request.content.badge)
        XCTAssertNil(request.trigger)

        let suppressed = AtomicBool(false)
        let delegate = NotificationCenterDelegate(
            onServiceRequested: { _ in }, isPresentationSuppressed: { suppressed.value }
        )
        XCTAssertEqual(delegate.presentationOptions(for: request), [.sound])
        let banner = UNNotificationRequest(
            identifier: "normal-notification", content: request.content, trigger: nil
        )
        XCTAssertEqual(delegate.presentationOptions(for: banner), [.banner, .sound])
        suppressed.value = true
        XCTAssertEqual(delegate.presentationOptions(for: request), [])
        XCTAssertEqual(delegate.presentationOptions(for: banner), [])
        player.stop()
    }

    func testLateAcceptanceCannotCancelTheNextSessionAndStopRejectsSounds() async throws {
        let center = RecordingIslandSoundCenter()
        let player = IslandNotificationSoundPlayer(center: center)
        player.play()
        let first = try XCTUnwrap(center.requests.first).identifier
        player.cancel()
        XCTAssertEqual(center.removed, [first])

        player.play()
        let next = try XCTUnwrap(center.requests.last).identifier
        XCTAssertNotEqual(first, next)
        center.completions[0](nil)
        await Task.yield()
        XCTAssertFalse(center.removed.contains(next))
        XCTAssertEqual(center.removed.filter { $0 == first }.count, 2)

        player.stop()
        XCTAssertTrue(center.removed.contains(next))
        center.completions[1](nil)
        await Task.yield()
        XCTAssertEqual(center.removed.filter { $0 == next }.count, 2)
        player.play()
        XCTAssertEqual(center.requests.count, 2)
    }
}

@MainActor
final class RecordingIslandSoundCenter: IslandNotificationSoundDelivering {
    var requests: [UNNotificationRequest] = []
    var completions: [@Sendable (Error?) -> Void] = []
    var removed: [String] = []

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
        requests.append(request)
        completions.append(completion)
    }

    func remove(identifier: String) { removed.append(identifier) }
}
