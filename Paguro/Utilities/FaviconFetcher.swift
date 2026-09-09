import Foundation
import Darwin

actor FaviconFetcher {
    static let shared = FaviconFetcher()

    /// Whether the Google favicon fallback may run. Off unless the user opts in,
    /// because that request tells Google which services the user runs — and the
    /// host can be a private one (a self-hosted Mattermost, an internal mail
    /// server) typed into "Add service". Every other source in this file is
    /// fetched from the service's own host, so this is the one third party in
    /// the path. `AppState` pushes the preference in on load and on change.
    private(set) var googleFallbackEnabled = false

    func setGoogleFallbackEnabled(_ enabled: Bool) {
        // Imported or previously saved preferences cannot enable Store traffic.
        googleFallbackEnabled = enabled && AppCapabilities.googleIconFallbackSupported
    }

    func fetchFavicon(for urlString: String) async -> Data? {
        guard let baseURL = URL(string: urlString),
              let host = baseURL.host,
              let rootURL = Self.originRootURL(for: baseURL)
        else { return nil }

        // A direct image URL is an explicit user choice in the service editor.
        if Self.directImageExtensions.contains(baseURL.pathExtension.lowercased()),
           let data = await fetchURL(baseURL.absoluteString),
           isValidImage(data) {
            return data
        }

        // Try common high-resolution paths first, then lower-resolution paths.
        // Resolve them from the origin so a custom port is preserved.
        let candidatePaths = [
            "apple-touch-icon.png",
            "apple-touch-icon-precomposed.png",
            "favicon-192x192.png",
            "favicon-96x96.png",
            "favicon-32x32.png",
            "favicon.ico",
        ]

        for path in candidatePaths {
            let candidate = rootURL.appending(path: path).absoluteString
            if let data = await fetchURL(candidate), isValidImage(data) {
                AppLogger.favicon.debug("Favicon found at \(candidate, privacy: .private)")
                return data
            }
        }

        // Try HTML icon links and the linked web-app manifest.
        if let data = await fetchFromHTMLLinks(url: baseURL) {
            return data
        }

        #if !APP_STORE
        // Google favicon API fallback — opt-in only; see googleFallbackEnabled.
        // Never send a likely-private host (self-hosted, intranet, literal
        // private IP) to Google even when the toggle is on: those hostnames are
        // the ones a user would least expect to leak off-device.
        if googleFallbackEnabled, !Self.isLikelyPrivateHost(host) {
            let googleAPI = "https://www.google.com/s2/favicons?domain=\(host)&sz=128"
            if let data = await fetchURL(googleAPI), isValidImage(data) {
                AppLogger.favicon.debug("Favicon from Google API for \(host, privacy: .private)")
                return data
            }
        }
        #endif

        AppLogger.favicon.debug("No favicon found for \(host, privacy: .private)")
        return nil
    }

    private func fetchFromHTMLLinks(url: URL) async -> Data? {
        guard let htmlData = await fetchURL(url.absoluteString),
              let html = String(data: htmlData, encoding: .utf8)
        else { return nil }

        var iconURLs = Self.parseIconLinks(from: html, baseURL: url)

        // A page can link to more than one manifest, but a small cap prevents a
        // hostile page from turning icon discovery into an unbounded fetch loop.
        for manifestURL in Self.parseManifestURLs(from: html, baseURL: url).prefix(3) {
            guard Self.isFetchableIconURL(manifestURL),
                  let manifestData = await fetchURL(manifestURL.absoluteString)
            else { continue }
            iconURLs.append(
                contentsOf: Self.parseManifestIconLinks(
                    from: manifestData,
                    manifestURL: manifestURL
                )
            )
        }

        // Sort by size descending — prefer largest icon
        let sorted = iconURLs.sorted { $0.size > $1.size }

        for iconInfo in sorted.prefix(32) {
            // The href came from (possibly hostile / compromised) page HTML, so
            // gate it: http/https only, no loopback/link-local/private hosts.
            // Without this a `<link rel=icon href="file:///…">` or an internal-IP
            // href would make this non-sandboxed app read local files / hit
            // internal hosts (SSRF).
            guard let iconURL = URL(string: iconInfo.url), Self.isFetchableIconURL(iconURL) else {
                continue
            }
            if let data = await fetchURL(iconInfo.url), isValidImage(data) {
                AppLogger.favicon.debug("Favicon from HTML link: \(iconInfo.url, privacy: .private)")
                return data
            }
        }

        return nil
    }

    /// Whether an icon URL parsed from page HTML is safe to fetch: http/https
    /// only and not aimed at a loopback/link-local/private host.
    nonisolated static func isFetchableIconURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return !isLikelyPrivateHost(host)
    }

    /// Hosts we never fetch a parsed href from and never send to a third party:
    /// literal private/reserved IPs, `localhost`, single-label intranet names
    /// (no dot), and private-use TLDs. A DNS-resolving check is deliberately out
    /// of scope — this cheap name test catches the common self-hosted/intranet
    /// shapes without a lookup, and the redirect guard covers the rest at fetch
    /// time.
    nonisolated static func isLikelyPrivateHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if isPrivateOrReservedHost(h) { return true }
        if h == "localhost" || h.hasSuffix(".localhost") { return true }
        if !h.contains(".") { return true }  // single-label intranet name
        let privateTLDs: Set<String> = [
            "local", "internal", "lan", "corp", "home", "test", "intranet", "localdomain",
        ]
        if let tld = h.split(separator: ".").last, privateTLDs.contains(String(tld)) {
            return true
        }
        return false
    }

    /// Recognizes literal loopback / link-local / private / reserved IPs so they
    /// can't be reached via a parsed favicon href. A normal hostname (not a
    /// literal IP) returns false — DNS-level rebinding is out of scope.
    nonisolated static func isPrivateOrReservedHost(_ host: String) -> Bool {
        let unbracketed = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host
        if let octets = ipv4Octets(unbracketed) {
            return isPrivateOrReservedIPv4(octets)
        }

        guard let octets = ipv6Octets(unbracketed) else {
            return false
        }

        if octets.allSatisfy({ $0 == 0 }) { return true }
        if octets.dropLast().allSatisfy({ $0 == 0 }), octets.last == 1 { return true }
        if octets[0] == 0xFE, octets[1] & 0xC0 == 0x80 { return true }
        if octets[0] & 0xFE == 0xFC { return true }

        let mappedPrefix = octets.prefix(10).allSatisfy { $0 == 0 }
            && octets[10] == 0xFF
            && octets[11] == 0xFF
        if mappedPrefix {
            return isPrivateOrReservedIPv4(Array(octets.suffix(4)))
        }
        return false
    }

    private nonisolated static func isPrivateOrReservedIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return false }
        let a = Int(octets[0])
        let b = Int(octets[1])
        switch a {
        case 0, 10, 127: return true                         // this-network, private, loopback
        case 100 where (64...127).contains(b): return true   // shared address space
        case 169 where b == 254: return true                 // link-local
        case 172 where (16...31).contains(b): return true    // private
        case 192 where b == 168: return true                 // private
        default: return false
        }
    }

    /// `inet_aton` also recognizes the shortened IPv4 forms accepted by URL
    /// loading, such as `127.1`. A dotted-quad-only parser would let those forms
    /// bypass the loopback check.
    private nonisolated static func ipv4Octets(_ host: String) -> [UInt8]? {
        var address = in_addr()
        guard host.withCString({ inet_aton($0, &address) }) == 1 else { return nil }
        let value = UInt32(bigEndian: address.s_addr)
        return [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    private nonisolated static func ipv6Octets(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    struct IconLink: Equatable {
        let url: String
        let size: Int
    }

    private struct Manifest: Decodable {
        let icons: [ManifestIcon]?
    }

    private struct ManifestIcon: Decodable {
        let src: String
        let sizes: String?
        let purpose: String?
    }

    nonisolated static func parseIconLinks(from html: String, baseURL: URL) -> [IconLink] {
        var results: [IconLink] = []

        let linkPattern = /<link\b[^>]*>/.ignoresCase()

        for match in html.matches(of: linkPattern) {
            let tag = String(match.output)
            guard let rel = attributeValue(in: tag, named: "rel")?.lowercased() else { continue }
            let relTokens = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
            guard relTokens.contains("icon") || relTokens.contains("apple-touch-icon") else { continue }

            guard let href = attributeValue(in: tag, named: "href"),
                  let resolvedURL = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }

            // Extract size hint
            let size = attributeValue(in: tag, named: "sizes").map(Self.largestIconSize) ?? 0

            results.append(IconLink(url: resolvedURL.absoluteString, size: size))
        }

        return results
    }

    nonisolated static func parseManifestURLs(from html: String, baseURL: URL) -> [URL] {
        let linkPattern = /<link\b[^>]*>/.ignoresCase()

        return html.matches(of: linkPattern).compactMap { match in
            let tag = String(match.output)
            guard let rel = attributeValue(in: tag, named: "rel")?.lowercased() else {
                return nil
            }
            let relTokens = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
            guard relTokens.contains("manifest"),
                  let href = attributeValue(in: tag, named: "href")
            else {
                return nil
            }
            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }
    }

    nonisolated static func parseManifestIconLinks(
        from data: Data,
        manifestURL: URL
    ) -> [IconLink] {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return []
        }

        return (manifest.icons ?? []).prefix(64).compactMap { icon in
            let purposes = Set(
                (icon.purpose ?? "any")
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            // A monochrome-only resource is meant to be recolored by its user
            // agent. Paguro needs a normal or maskable full-color service icon.
            guard purposes.contains("any") || purposes.contains("maskable"),
                  let resolvedURL = URL(string: icon.src, relativeTo: manifestURL)?.absoluteURL
            else {
                return nil
            }

            let size = icon.sizes.map(Self.largestIconSize) ?? 0
            return IconLink(url: resolvedURL.absoluteString, size: size)
        }
    }

    nonisolated private static func attributeValue(in tag: String, named name: String) -> String? {
        let pattern = #"(?i)\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[valueRange])
    }

    nonisolated private static func largestIconSize(from sizes: String) -> Int {
        if sizes.lowercased().split(whereSeparator: \.isWhitespace).contains("any") {
            return 4096
        }
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)x\d+"#) else { return 0 }
        let range = NSRange(sizes.startIndex..<sizes.endIndex, in: sizes)
        return regex.matches(in: sizes, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: sizes) else { return nil }
            return Int(sizes[valueRange])
        }.max() ?? 0
    }

    nonisolated private static func originRootURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            return nil
        }
        components.scheme = scheme
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static let directImageExtensions: Set<String> = [
        "gif", "icns", "ico", "jpeg", "jpg", "png", "svg", "webp",
    ]

    /// Hard ceiling on any single fetch (favicon or the HTML we parse for links).
    /// Favicons are KBs; this only exists to stop a hostile/broken endpoint from
    /// streaming a huge body into memory.
    private static let maxFetchBytes = 5 * 1024 * 1024  // 5 MB

    /// Re-validates every redirect hop with the same rule as the initial href
    /// check. Without it a public-host icon href could 302 to a loopback /
    /// link-local / private / non-http target and this non-sandboxed app would
    /// follow it (SSRF via redirect), since the initial `isFetchableIconURL`
    /// guard only ever sees the first URL. Stateless, so one shared instance.
    private static let redirectGuard = FaviconRedirectGuard()

    private func fetchURL(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            // Stream so we can stop at the cap instead of buffering an unbounded
            // response all at once (memory DoS via an oversized favicon/HTML body).
            // The per-task delegate re-checks each redirect target (SSRF guard).
            let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: Self.redirectGuard)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            if http.expectedContentLength > Int64(Self.maxFetchBytes) { return nil }

            var data = Data()
            if http.expectedContentLength > 0 {
                data.reserveCapacity(min(Int(http.expectedContentLength), Self.maxFetchBytes))
            }
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxFetchBytes { return nil }
            }
            return data.isEmpty ? nil : data
        } catch {
            AppLogger.favicon.debug("Fetch failed for \(urlString, privacy: .private): \(error.localizedDescription)")
        }
        return nil
    }

    private func isValidImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let header = [UInt8](data.prefix(4))
        // PNG
        if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 { return true }
        // JPEG
        if header[0] == 0xFF && header[1] == 0xD8 { return true }
        // ICO
        if header[0] == 0x00 && header[1] == 0x00 && header[2] == 0x01 && header[3] == 0x00 { return true }
        // GIF
        if header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 { return true }
        // Apple icon image
        if header == [0x69, 0x63, 0x6E, 0x73] { return true } // "icns"
        // WebP: the container is "RIFF"<size>"WEBP". Verify the WEBP tag at
        // bytes 8–11, not just the RIFF magic — WAV/AVI are also RIFF and would
        // be cached as junk that never renders.
        if data.count >= 12,
           header[0] == 0x52, header[1] == 0x49, header[2] == 0x46, header[3] == 0x46 {
            let tag = [UInt8](data.prefix(12).suffix(4))
            if tag == [0x57, 0x45, 0x42, 0x50] { return true }  // "WEBP"
        }
        // SVG is text, not a binary magic number; sniff the head for an <svg
        // root. NSImage renders SVG on modern macOS, so accept it rather than
        // rejecting it and falling through to the lower-res Google API.
        if Self.looksLikeSVG(data) { return true }
        return false
    }

    /// Whether `data` is an SVG document — its *root* element is `<svg`, past an
    /// optional BOM, XML declaration, and leading comments. Anchored at the root
    /// (not "contains <svg anywhere") so an HTML page with an inline `<svg>` icon
    /// — e.g. an SPA index returned with 200 for an unknown /favicon path — isn't
    /// false-accepted and cached as a non-rendering image. UTF-8 only (SVG is
    /// text); the isoLatin1 fallback that never fails is deliberately dropped.
    nonisolated private static func looksLikeSVG(_ data: Data) -> Bool {
        let head = data.prefix(1024)
        guard var text = String(data: head, encoding: .utf8) else { return false }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("<?xml"), let close = text.range(of: "?>") {
            text = String(text[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while text.hasPrefix("<!--"), let close = text.range(of: "-->") {
            text = String(text[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = text.lowercased()
        return lower.hasPrefix("<svg") || lower.hasPrefix("<!doctype svg")
    }
}

/// Task delegate that cancels a redirect aimed at a host the favicon fetcher's
/// initial `isFetchableIconURL` check would have rejected. Returning `nil` stops
/// URLSession from following the 3xx, so the fetch sees the redirect response
/// (not the internal target) and its `statusCode == 200` guard discards it.
/// Stateless, so safe to share across tasks.
private final class FaviconRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, FaviconFetcher.isFetchableIconURL(url) else { return nil }
        return request
    }
}
