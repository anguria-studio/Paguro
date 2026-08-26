import Foundation

/// Pure rules for service ownership, popup routing, and external URL handoff.
public enum WebRoutingPolicy {
    private static let externalSchemes: Set<String> = [
        "http", "https", "mailto", "tel", "sms", "facetime",
        "facetime-audio", "imessage", "maps",
    ]

    private static let sharedUmbrellaDomains: Set<String> = [
        "google.com",
        "microsoft.com",
        "live.com",
        "yahoo.com",
        "apple.com",
        "amazon.com",
    ]

    private static let sharedHostingSuffixes: Set<String> = [
        "github.io", "gitlab.io", "web.app", "firebaseapp.com", "appspot.com",
        "run.app", "pages.dev", "workers.dev", "vercel.app", "netlify.app",
        "herokuapp.com", "onrender.com", "fly.dev", "glitch.me", "repl.co",
        "replit.dev", "surge.sh", "azurewebsites.net",
    ]

    private static let authenticationHosts: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com",
        "login.microsoftonline.com",
        "login.microsoft.com",
        "login.windows.net",
        "login.live.com",
        "login.yahoo.com",
        "appleid.apple.com",
        "idmsa.apple.com",
    ]

    private static let twoPartTopLevelDomains: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk",
        "com.au", "net.au", "org.au", "edu.au",
        "co.nz", "net.nz", "org.nz",
        "co.jp", "or.jp", "ne.jp",
        "com.br", "org.br", "net.br",
        "co.kr", "or.kr",
        "co.in", "net.in", "org.in",
        "com.cn", "net.cn", "org.cn",
        "co.za", "org.za",
        "com.mx", "org.mx",
        "co.il", "org.il",
        "com.sg", "org.sg",
        "com.hk", "org.hk",
        "co.th", "or.th",
    ]

    /// Returns whether two hosts belong to one service.
    ///
    /// Normal domains allow sibling subdomains. Shared product domains require
    /// an exact host. Shared hosting keeps each tenant separate.
    public static func belongsToService(_ targetHost: String, serviceHost: String) -> Bool {
        let target = normalizedHost(targetHost)
        let service = normalizedHost(serviceHost)
        guard !target.isEmpty, !service.isEmpty else { return false }

        let targetDomain = registrableDomain(target)
        guard targetDomain == registrableDomain(service) else { return false }
        if sharedUmbrellaDomains.contains(targetDomain) {
            return target == service
        }
        return true
    }

    /// Returns whether a host is a known sign-in gateway or its subdomain.
    public static func isAuthenticationHost(_ host: String) -> Bool {
        let normalized = normalizedHost(host)
        return authenticationHosts.contains(normalized)
            || authenticationHosts.contains { normalized.hasSuffix("." + $0) }
    }

    /// Returns whether a clicked same-service popup should load in its opener.
    public static func shouldLoadNewWindowInPlace(
        isLinkActivated: Bool,
        targetHost: String?,
        openerHost: String?
    ) -> Bool {
        guard isLinkActivated, let targetHost, let openerHost else { return false }
        return belongsToService(targetHost, serviceHost: openerHost)
    }

    /// Returns whether closing a popup should reload its opener.
    public static func shouldReloadOpener(
        selfClosed: Bool,
        openedAtAuthenticationHost: Bool
    ) -> Bool {
        selfClosed || openedAtAuthenticationHost
    }

    /// Returns whether an authentication popup has returned to its service.
    public static func shouldCloseAuthenticationPopup(
        openedAtAuthenticationHost: Bool,
        landedHost: String?,
        openerHost: String?
    ) -> Bool {
        guard openedAtAuthenticationHost, let landedHost, let openerHost else {
            return false
        }
        return belongsToService(landedHost, serviceHost: openerHost)
    }

    /// Returns whether Atoll can hand a URL to the system safely.
    public static func isSafeForExternalOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return externalSchemes.contains(scheme)
    }

    /// Reduces a server-suggested filename to one safe path component.
    public static func sanitizedDownloadFilename(_ suggested: String) -> String {
        let cleaned = (suggested as NSString).lastPathComponent
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." || cleaned == "-" {
            return "download"
        }
        return cleaned
    }

    private static func registrableDomain(_ host: String) -> String {
        let normalized = normalizedHost(host)
        let parts = normalized.split(separator: ".")
        guard parts.count >= 2 else { return normalized }

        for suffix in sharedHostingSuffixes {
            if normalized == suffix { return normalized }
            if normalized.hasSuffix("." + suffix) {
                let labelCount = suffix.split(separator: ".").count + 1
                return parts.suffix(labelCount).joined(separator: ".")
            }
        }

        let lastTwo = parts.suffix(2).joined(separator: ".")
        if twoPartTopLevelDomains.contains(lastTwo), parts.count >= 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    private static func normalizedHost(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }
        return normalized
    }
}
