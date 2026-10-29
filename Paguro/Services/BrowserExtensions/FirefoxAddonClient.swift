#if !APP_STORE
import CryptoKit
import Foundation
import PaguroCore

struct FirefoxAddonPackage: Sendable {
    let slug: String
    let version: String
    let sha256: String
    let data: Data
}

struct FirefoxAddonClient: Sendable {
    private let readData: (@Sendable (URL, Int) async throws -> Data)?

    init(read: (@Sendable (URL, Int) async throws -> Data)? = nil) { readData = read }

    private func read(_ url: URL, limit: Int, timeout: TimeInterval) async throws -> Data {
        if let readData { return try await readData(url, limit) }
        return try await Self.readNetwork(url, limit: limit, timeout: timeout)
    }

    private struct Addon: Decodable {
        let slug: String
        let type: String
        let is_disabled: Bool
        let current_version: Version
        struct Version: Decodable {
            let version: String
            let file: File
        }
        struct File: Decodable {
            let url: URL
            let hash: String
            let size: Int
            let status: String
        }
    }

    func latest(_ source: FirefoxAddonSource) async throws -> FirefoxAddonRelease {
        let metadata = try await read(source.metadataURL, limit: 2 * 1_024 * 1_024, timeout: 30)
        guard metadata.count <= 2 * 1_024 * 1_024 else { throw Failure.tooLarge }
        let addon = try JSONDecoder().decode(Addon.self, from: metadata)
        let file = addon.current_version.file
        guard addon.type == "extension", !addon.is_disabled, file.status == "public",
              addon.slug == source.slug, file.hash.hasPrefix("sha256:") else { throw Failure.unavailable }
        let release = FirefoxAddonRelease(slug: addon.slug, version: addon.current_version.version,
            sha256: String(file.hash.dropFirst(7)), downloadURL: file.url, size: file.size)
        guard release.isValid else { throw Failure.unavailable }
        return release
    }

    func fetch(_ source: FirefoxAddonSource) async throws -> FirefoxAddonPackage {
        let release = try await latest(source)
        let data = try await read(release.downloadURL, limit: release.size, timeout: 120)
        let digest = Self.digest(data)
        guard data.count == release.size, digest == release.sha256 else { throw Failure.invalidHash }
        try ExtensionArchivePolicy.validate(data)
        return FirefoxAddonPackage(slug: release.slug, version: release.version, sha256: digest, data: data)
    }

    nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readNetwork(_ url: URL, limit: Int, timeout: TimeInterval) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: MozillaRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, FirefoxAddonSource.isTrustedDownloadURL(finalURL),
              response.expectedContentLength <= limit else { throw Failure.unavailable }
        var data = Data()
        data.reserveCapacity(min(limit, 1_024 * 1_024))
        for try await byte in bytes {
            guard data.count < limit else { throw Failure.tooLarge }
            data.append(byte)
            // A cancellation check per byte is measurable on a 64 MiB package.
            if data.count.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return data
    }

    enum Failure: Error, LocalizedError {
        case unavailable, invalidHash, tooLarge
        var errorDescription: String? {
            switch self {
            case .unavailable: "Firefox Add-ons did not provide a supported public extension package."
            case .invalidHash: "The extension package does not match the checksum from Firefox Add-ons."
            case .tooLarge: "The extension download exceeds the prototype's size limit."
            }
        }
    }
}

private final class MozillaRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(FirefoxAddonSource.isTrustedDownloadURL) == true ? request : nil)
    }
}
#endif
