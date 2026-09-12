import AppKit
import XCTest
@testable import Paguro

@MainActor
final class ServiceIconDraftTests: XCTestCase {
    func testTypingWaitsAndOnlyFetchesTheLatestAddress() async throws {
        let gate = IconDraftGate()
        let requests = IconDraftRequests()
        let draft = ServiceIconDraft(fetch: { await requests.fetch($0) }, pause: { await gate.wait() })
        draft.updateURL("https://first.example")
        try await waitUntil { gate.waiters.count == 1 }
        draft.updateURL("https://second.example")
        try await waitUntil { gate.waiters.count == 2 }
        XCTAssertTrue(requests.urls.isEmpty)
        gate.open()
        try await waitUntil { requests.urls.count == 1 }
        XCTAssertEqual(requests.urls, ["https://second.example"])
        let data = try icon(.systemTeal)
        requests.finish("https://second.example", data: data)
        try await waitUntil { !draft.isFetching }
        XCTAssertNotNil(draft.fetchedIconData)
        XCTAssertNil(draft.customIconData)
        XCTAssertNil(draft.fetchedIcon(for: "https://first.example"))
    }

    func testAnOldResponseCannotReplaceTheCurrentWebsiteIcon() async throws {
        let requests = IconDraftRequests()
        let draft = ServiceIconDraft(fetch: { await requests.fetch($0) }, pause: {})
        draft.updateURL("https://first.example")
        try await waitUntil { requests.urls.count == 1 }
        draft.updateURL("https://second.example")
        XCTAssertNil(draft.fetchedIconData)
        try await waitUntil { requests.urls.count == 2 }
        requests.finish("https://second.example", data: try icon(.systemTeal))
        try await waitUntil { !draft.isFetching }
        let current = try XCTUnwrap(draft.fetchedIconData)
        requests.finish("https://first.example", data: try icon(.systemRed))
        try await waitUntil { requests.completed == 2 }
        XCTAssertEqual(draft.fetchedIconData, current)
    }

    func testChoosingAnImageSurvivesALateFetchAndCanResetToWebsite() async throws {
        let requests = IconDraftRequests()
        let draft = ServiceIconDraft(fetch: { await requests.fetch($0) }, pause: {})
        draft.updateURL("https://example.com")
        try await waitUntil { requests.urls.count == 1 }
        draft.chooseImage(try icon(.systemRed))
        let custom = try XCTUnwrap(draft.customIconData)
        requests.finish("https://example.com", data: try icon(.systemTeal))
        try await waitUntil { requests.completed == 1 }
        XCTAssertEqual(draft.customIconData, custom)
        XCTAssertNil(draft.fetchedIconData)
        XCTAssertFalse(draft.isFetching)
        draft.useWebsiteIcon()
        XCTAssertNil(draft.customIconData)
        try await waitUntil { requests.urls.count == 2 }
        requests.finish("https://example.com", data: try icon(.systemTeal))
        try await waitUntil { !draft.isFetching }
        XCTAssertNotNil(draft.fetchedIconData)
    }

    func testDismissalDiscardsPendingWorkAndMissingIconsKeepTheFallback() async throws {
        let requests = IconDraftRequests()
        let draft = ServiceIconDraft(fetch: { await requests.fetch($0) }, pause: {})
        draft.updateURL("https://example.com")
        try await waitUntil { requests.urls.count == 1 }
        draft.cancel()
        requests.finish("https://example.com", data: try icon(.systemTeal))
        try await waitUntil { requests.completed == 1 }
        XCTAssertNil(draft.fetchedIconData)
        XCTAssertFalse(draft.isFetching)
        draft.updateURL("https://example.com")
        try await waitUntil { requests.urls.count == 2 }
        requests.finish("https://example.com", data: Data("not an image".utf8))
        try await waitUntil { !draft.isFetching }
        XCTAssertNil(draft.fetchedIconData)
        XCTAssertNil(draft.errorMessage)
    }

    func testClearingOrInvalidatingTheAddressClearsItsAutomaticIcon() async throws {
        let data = try icon(.systemTeal)
        let draft = ServiceIconDraft(fetch: { _ in data }, pause: {})
        draft.updateURL("https:")
        XCTAssertFalse(draft.isFetching)
        draft.updateURL("example.com")
        XCTAssertFalse(draft.isFetching)
        draft.updateURL("https://example.com")
        try await waitUntil { !draft.isFetching }
        XCTAssertNotNil(draft.fetchedIconData)
        draft.updateURL("file:///private/image.png")
        XCTAssertNil(draft.fetchedIconData)
        XCTAssertFalse(draft.isFetching)
        draft.updateURL("")
        XCTAssertNil(draft.fetchedIconData)
    }

    private func icon(_ color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        return try ServiceIconImageProcessor.normalizedPNG(from: image)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Icon operation did not finish")
    }
}

@MainActor
private final class IconDraftRequests {
    var urls: [String] = []
    var completed = 0
    private var pending: [String: CheckedContinuation<Data?, Never>] = [:]

    func fetch(_ url: String) async -> Data? {
        urls.append(url)
        let data = await withCheckedContinuation { pending[url] = $0 }
        completed += 1
        return data
    }

    func finish(_ url: String, data: Data?) {
        pending.removeValue(forKey: url)?.resume(returning: data)
    }
}

@MainActor
private final class IconDraftGate {
    var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { await withCheckedContinuation { waiters.append($0) } }
    func open() {
        let current = waiters
        waiters = []
        current.forEach { $0.resume() }
    }
}
