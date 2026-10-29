import AppKit
import XCTest

/// Popup tests check real keyboard focus, and only the active app can own a
/// key window. macOS can refuse to activate the test host while the person
/// works in another app. That is a test environment limit, not a failure.
@MainActor
enum PopupFocus {
    static func requireActiveApp() async throws {
        NSApp.activate()
        for _ in 0..<150 {
            if NSApp.isActive { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XCTSkip("macOS did not activate the test host, so popup focus cannot be checked. Run again with no other app in use.")
    }
}
