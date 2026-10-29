#if !APP_STORE
import Foundation
import PaguroCore
@testable import Paguro

/// Research downloads only. The application does not install Chrome packages.
struct ExtensionComparisonPackage: Sendable {
    let package: FirefoxAddonPackage
    let source: String
    let downloadURL: URL
    let transportSHA256: String

    static let chromeIDs = [
        "bitwarden-password-manager": "nngceckbapebfimnlniiiahkandclblb",
        "darkreader": "eimadpbcbfnmbkopoojfekhnkhdbieeh",
        "simple-translate": "ibplnjkanclpjokhdolnendpplpjiace",
        "grammarly-1": "kbfnbcaeplbcioakkpcpgfkobkghlhen",
        "tampermonkey": "dhdgffkkebhmkfjojejmpbldmpobfkfo"
    ]

    static func fetchChrome(slug: String) async throws -> Self {
        guard let id = chromeIDs[slug] else { throw Failure.unknownPackage }
        var url = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        url.queryItems = [URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "143.0.0.0"),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&uc")]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: ComparisonRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let final = http.url, isDownloadURL(final),
              response.expectedContentLength <= ExtensionArchivePolicy.maximumDownloadBytes else { throw Failure.download }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < ExtensionArchivePolicy.maximumDownloadBytes else { throw Failure.download }
            data.append(byte)
        }
        let archive = try archive(from: data)
        // The version is read from WebKit's manifest after archive validation.
        return Self(package: FirefoxAddonPackage(slug: slug, version: "pending manifest", sha256: FirefoxAddonClient.digest(archive), data: archive),
            source: "chrome", downloadURL: url.url!, transportSHA256: FirefoxAddonClient.digest(data))
    }

    /// Remove only the CRX3 envelope. This does not verify CRX publisher proofs.
    static func archive(from data: Data) throws -> Data {
        guard data.count >= 12, data.count <= ExtensionArchivePolicy.maximumDownloadBytes,
              Array(data.prefix(8)) == [67, 114, 50, 52, 3, 0, 0, 0] else { throw Failure.envelope }
        let length = data.dropFirst(8).prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        guard length <= 1_024 * 1_024, 12 + length < data.count else { throw Failure.envelope }
        let archive = Data(data.dropFirst(12 + length))
        try ExtensionArchivePolicy.validate(archive)
        return archive
    }

    static func isDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil
            && ["clients2.google.com", "clients2.googleusercontent.com"].contains(url.host?.lowercased() ?? "")
    }

    enum Failure: Error { case unknownPackage, download, envelope }
}

private final class ComparisonRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(ExtensionComparisonPackage.isDownloadURL) == true ? request : nil)
    }
}
#endif
