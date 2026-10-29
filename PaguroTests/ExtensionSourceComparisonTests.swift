#if !APP_STORE
import Foundation
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class ExtensionSourceComparisonTests: XCTestCase {
    @available(macOS 15.4, *)
    struct Result: Codable {
        let source: String
        let downloadURL: URL
        let transportSHA256: String
        let archiveSHA256: String
        let manifest: String
        let manifestErrors: [String]
        let loadError: String?
        let runtime: ExtensionCompatibilityProbe.Report?
    }

    func testFirefoxAndChromePackagesWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live source comparison. See EXTENSION-COMPATIBILITY.md.")
        }
        let slug = ProcessInfo.processInfo.environment["PAGURO_EXTENSION_PROBE_SLUG"] ?? "bitwarden-password-manager"
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/\(slug)/")
        let firefox = try await FirefoxAddonClient().fetch(source)
        let packages = [ExtensionComparisonPackage(package: firefox, source: "firefox", downloadURL: source.metadataURL,
            transportSHA256: firefox.sha256), try await ExtensionComparisonPackage.fetchChrome(slug: slug)]
        var versions: [String: String] = [:]
        for input in packages {
            let file = FileManager.default.temporaryDirectory.appending(path: "source-comparison-\(UUID().uuidString).zip")
            try input.package.data.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let webExtension = try await WKWebExtension(resourceBaseURL: file)
            let version = webExtension.manifest["version"] as? String ?? "unknown"
            versions[input.source] = version
            let package = FirefoxAddonPackage(slug: slug, version: version, sha256: input.package.sha256, data: input.package.data)
            let manifest = String(decoding: try JSONSerialization.data(withJSONObject: webExtension.manifest, options: [.sortedKeys]), as: UTF8.self)
            let errors = webExtension.errors.map(\.localizedDescription)
            // Match the installer's manifest gate. Do not bypass a rejected package.
            if !errors.isEmpty {
                try attach(Result(source: input.source, downloadURL: input.downloadURL, transportSHA256: input.transportSHA256,
                    archiveSHA256: package.sha256, manifest: manifest, manifestErrors: errors, loadError: nil, runtime: nil), name: "\(slug)-\(input.source)-manifest")
                continue
            }
            for identity in [ExtensionCompatibilityProbe.Identity.webKit, .firefox, .chrome] {
                let probe = ExtensionCompatibilityProbe(identity: identity, matchServiceIdentity: true)
                defer { probe.close() }
                let id = UUID()
                var loadError: String?
                do {
                    try probe.load(webExtension, id: id)
                    probe.loadServiceFixture()
                    for _ in 0..<100 {
                        if probe.isServiceFixtureReady { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    probe.recordServiceState()
                    probe.session.didNavigate()
                    try await Task.sleep(for: .seconds(2))
                    probe.snapshotService(label: "service.initial")
                    try probe.openPopup(id: id)
                    try await Task.sleep(for: .seconds(8))
                    probe.snapshotPopup()
                    try await Task.sleep(for: .milliseconds(100))
                    await exercise(slug: slug, probe: probe)
                    await probe.snapshotPages()
                } catch { loadError = error.localizedDescription }
                let result = Result(source: input.source, downloadURL: input.downloadURL, transportSHA256: input.transportSHA256,
                    archiveSHA256: package.sha256, manifest: manifest, manifestErrors: errors, loadError: loadError, runtime: probe.report(package: package, identity: identity))
                try attach(result, name: "\(slug)-\(input.source)-\(identity.rawValue)")
            }
        }
        print("EXTENSION SOURCE VERSIONS: \(slug), \(versions), matched=\(Set(versions.values).count == 1)")
    }

    @available(macOS 15.4, *)
    private func exercise(slug: String, probe: ExtensionCompatibilityProbe) async {
        switch slug {
        case "bitwarden-password-manager":
            probe.evaluatePopup("""
                const login = Array.from(document.querySelectorAll('a,button')).find(e => e.textContent.trim() === 'Log in');
                login?.click();
                return JSON.stringify({loginActionFound:!!login});
                """, label: "login.opened")
            try? await Task.sleep(for: .seconds(2))
            probe.snapshotPopup()
        case "simple-translate":
            probe.evaluatePopup("""
                const action = Array.from(document.querySelectorAll('a')).find(e => e.textContent.includes('Translate this page'));
                action?.click();
                return JSON.stringify({translateActionFound:!!action});
                """, label: "translation.requested")
            for _ in 0..<250 {
                if let page = probe.session.pages.first, page.pageView.url != nil, !page.pageView.isLoading { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        case "darkreader":
            for mode in ["light", "dark"] {
                probe.evaluatePopup("""
                    const action = document.querySelector('.icon--\(mode)-mode')?.closest('button');
                    action?.click();
                    return JSON.stringify({mode:'\(mode)',modeActionFound:!!action});
                    """, label: "mode.\(mode).requested")
                try? await Task.sleep(for: .seconds(1))
                probe.snapshotService(label: "service.\(mode)")
            }
        default: break
        }
        try? await Task.sleep(for: .milliseconds(150))
    }

    @available(macOS 15.4, *)
    private func attach(_ result: Result, name: String) throws {
        let data = try JSONEncoder().encode(result)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("EXTENSION SOURCE REPORT: \(String(decoding: data, as: UTF8.self))")
    }
}
#endif
