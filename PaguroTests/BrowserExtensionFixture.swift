#if !APP_STORE
import Foundation
import WebKit
@testable import Paguro

@available(macOS 15.4, *)
enum BrowserExtensionFixture {
    static func package(version: String = "1.0", invalidManifest: Bool = false,
                        manifestVersion: Int = 2, additionalPermissions: [String] = [],
                        backgroundScript: String = "browser.runtime.onMessage.addListener(() => Promise.resolve({working:true}));") throws -> FirefoxAddonPackage {
        var manifest: [String: Any] = [
            "manifest_version": 2, "name": "Paguro isolation probe", "version": version,
            "description": "Tests account isolation with synthetic data.",
            "permissions": ["storage", "cookies", "tabs", "https://example.com/*", "http://127.0.0.1/*"] + additionalPermissions,
            "optional_permissions": ["clipboardWrite", "https://optional.example/*"],
            "background": ["scripts": ["background.js"], "persistent": false],
            "options_ui": ["page": "probe.html", "open_in_tab": true],
            "browser_action": ["default_title": "Isolation probe", "default_popup": "probe.html"],
            "content_scripts": [["matches": ["https://example.com/*", "http://127.0.0.1/*"],
                                 "js": ["content.js"], "run_at": "document_end"]]
        ]
        if manifestVersion == 3 {
            manifest["manifest_version"] = 3
            manifest["permissions"] = ["storage", "cookies", "tabs"] + additionalPermissions
            manifest["host_permissions"] = ["https://example.com/*", "http://127.0.0.1/*"]
            manifest["optional_permissions"] = ["clipboardWrite"]
            manifest["optional_host_permissions"] = ["https://optional.example/*"]
            manifest["background"] = ["service_worker": "background.js"]
            manifest["action"] = manifest.removeValue(forKey: "browser_action")
        }
        if invalidManifest { manifest["content_scripts"] = "invalid" }
        let files = [
            ("manifest.json", try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])),
            ("probe.html", Data("<!doctype html><title>Extension probe</title><p>Isolation probe</p>".utf8)),
            ("content.js", Data("document.documentElement.dataset.paguroExtension = 'injected';".utf8)),
            ("background.js", Data(backgroundScript.utf8))
        ]
        let data = archive(files)
        return FirefoxAddonPackage(slug: "paguro-isolation-probe", version: version,
                                   sha256: FirefoxAddonClient.digest(data), data: data)
    }

    static func archive(_ files: [(String, Data)]) -> Data {
        var local = Data()
        var central = Data()
        for (name, contents) in files {
            let offset = local.count
            let bytes = Data(name.utf8)
            let crc = crc32(contents)
            local.le(0x04034b50, 4)
            for value in [20, 0, 0, 0, 0] { local.le(value, 2) }
            for value in [crc, contents.count, contents.count] { local.le(value, 4) }
            local.le(bytes.count, 2); local.le(0, 2)
            local.append(bytes); local.append(contents)
            central.le(0x02014b50, 4)
            for value in [0x0314, 20, 0, 0, 0, 0] { central.le(value, 2) }
            for value in [crc, contents.count, contents.count] { central.le(value, 4) }
            for value in [bytes.count, 0, 0, 0, 0] { central.le(value, 2) }
            central.le(0o100644 << 16, 4); central.le(offset, 4); central.append(bytes)
        }
        var result = local + central
        result.le(0x06054b50, 4)
        for value in [0, 0, files.count, files.count] { result.le(value, 2) }
        result.le(central.count, 4); result.le(local.count, 4); result.le(0, 2)
        return result
    }

    private static func crc32(_ data: Data) -> Int {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return Int(crc ^ 0xffffffff)
    }
}

private extension Data {
    mutating func le(_ value: Int, _ size: Int) {
        for i in 0..<size { append(UInt8(truncatingIfNeeded: value >> (i * 8))) }
    }
}
#endif
