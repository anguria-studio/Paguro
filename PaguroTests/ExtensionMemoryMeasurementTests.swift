#if !APP_STORE
import AppKit
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

/// Opt-in memory measurement for the extension prototype.
///
/// Run it through `scripts/measure_extension_memory.py`. This test only opens
/// throwaway accounts and holds each phase steady. The script measures the
/// test host's process group with `footprint` while a phase holds, because
/// WebKit helpers belong to the app's coalition, not to its process tree.
@MainActor
final class ExtensionMemoryMeasurementTests: XCTestCase {
    @available(macOS 15.4, *)
    private struct Extension {
        let slug: String
        let webExtension: WKWebExtension
        let profile: ExtensionRuntimeProfile
    }

    @available(macOS 15.4, *)
    private struct Account {
        let session: ServiceExtensionSession?
        let view: WKWebView
    }

    func testMemoryPhasesWhenExplicitlyRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PAGURO_EXTENSION_MEMORY"] == "1" else {
            throw XCTSkip("Opt-in memory measurement. Run scripts/measure_extension_memory.py.")
        }
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let counts = (environment["PAGURO_EXTENSION_MEMORY_COUNTS"] ?? "1,5,10")
            .split(separator: ",").compactMap { Int($0) }.filter { (1...20).contains($0) }
        let slugs = (environment["PAGURO_EXTENSION_MEMORY_SLUGS"] ?? "darkreader,bitwarden-password-manager,simple-translate")
            .split(separator: ",").map(String.init)
        let settle = Double(environment["PAGURO_EXTENSION_MEMORY_SETTLE"] ?? "") ?? 15
        let hold = Double(environment["PAGURO_EXTENSION_MEMORY_HOLD"] ?? "") ?? 25

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var extensions: [Extension] = []
        for slug in slugs {
            extensions.append(try await download(slug, into: directory))
        }

        for count in counts {
            try await measure(phase: "baseline", count: count, extension: nil, settle: settle, hold: hold)
            for item in extensions {
                try await measure(phase: item.slug, count: count, extension: item, settle: settle, hold: hold)
            }
        }
        marker("finished")
    }

    @available(macOS 15.4, *)
    private func download(_ slug: String, into directory: URL) async throws -> Extension {
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/\(slug)/")
        let package = try await FirefoxAddonClient().fetch(source)
        let file = directory.appending(path: "\(slug).zip")
        try package.data.write(to: file)
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        XCTAssertTrue(webExtension.errors.isEmpty, "\(slug) has manifest errors")
        marker("package slug=\(slug) version=\(package.version) sha256=\(package.sha256)")
        // Bitwarden only starts with the Firefox profile, so measure it the way it works.
        let profile: ExtensionRuntimeProfile = slug == "bitwarden-password-manager" ? .firefox : .standard
        return Extension(slug: slug, webExtension: webExtension, profile: profile)
    }

    @available(macOS 15.4, *)
    private func measure(phase: String, count: Int, extension item: Extension?,
                         settle: Double, hold: Double) async throws {
        // Let processes from the previous phase exit, then record the idle level.
        try await Task.sleep(for: .seconds(5))
        marker("idle phase=\(phase) services=\(count)")
        try await Task.sleep(for: .seconds(hold))

        var accounts: [Account] = []
        for _ in 0..<count { accounts.append(try openAccount(with: item)) }
        try await Task.sleep(for: .seconds(settle))
        marker("ready phase=\(phase) services=\(count)")
        try await Task.sleep(for: .seconds(hold))
        marker("done phase=\(phase) services=\(count)")

        for account in accounts {
            account.view.stopLoading()
            account.session?.close()
        }
        accounts.removeAll()
    }

    /// One throwaway account: its own nonpersistent store, one service view,
    /// and, when measured, its own extension controller, as the app does.
    @available(macOS 15.4, *)
    private func openAccount(with item: Extension?) throws -> Account {
        let store = WKWebsiteDataStore.nonPersistent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        var session: ServiceExtensionSession?
        if let item {
            let created = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store,
                                                  profile: item.profile)
            try created.load(item.webExtension, id: UUID())
            configuration.webExtensionController = created.controller
            if let name = item.profile.applicationNameForUserAgent {
                configuration.applicationNameForUserAgent = name
            }
            session = created
        }
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1_024, height: 768), configuration: configuration)
        session?.open(view)
        view.loadHTMLString(Self.servicePage, baseURL: URL(string: "https://example.com/"))
        return Account(session: session, view: view)
    }

    /// stderr is unbuffered, so the script sees each marker when it happens.
    private func marker(_ text: String) {
        FileHandle.standardError.write(Data("EXTENSION-MEMORY \(text)\n".utf8))
    }

    /// A small static page with text and a form, so content scripts have work.
    private static let servicePage: String = {
        let paragraph = "<p>Synthetic service content for memory measurement. It has no account data.</p>"
        return """
            <!doctype html><html><head><title>Service</title></head><body>
            <h1>Inbox</h1>\(String(repeating: paragraph, count: 200))
            <form><input name="username" autocomplete="username"><input type="password" name="password"></form>
            </body></html>
            """
    }()
}
#endif
