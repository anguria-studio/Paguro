#if !APP_STORE
import Foundation
import WebKit
@testable import Paguro

/// Disposable native-contract experiment. It never connects to a desktop app.
@available(macOS 15.4, *)
@MainActor
final class CompatibilityTimerHost: NSObject, WKWebExtensionControllerDelegate {
    private let session: ServiceExtensionSession
    private var pending: [Task<Void, any Error>] = []
    private(set) var sleepRequests = 0

    init(session: ServiceExtensionSession) { self.session = session }

    func cancel() {
        for task in pending { task.cancel() }
        pending.removeAll()
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        session.webExtensionController(controller, openWindowsFor: context)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        session.webExtensionController(controller, focusedWindowFor: context)
    }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any,
                                toApplicationWithIdentifier identifier: String?, for context: WKWebExtensionContext) async throws -> Any {
        guard identifier == "com.bitwarden.desktop", let payload = message as? [String: Any],
              payload["command"] as? String == "sleep", pending.count < 4 else { throw CocoaError(.featureUnsupported) }
        sleepRequests += 1
        let task = Task { try await Task.sleep(for: .seconds(10)) }
        pending.append(task)
        try await task.value
        return ["responseData": NSNull()]
    }
}
#endif
