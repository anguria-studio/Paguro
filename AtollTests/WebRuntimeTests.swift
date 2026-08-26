import XCTest
import AppKit
import JavaScriptCore
import WebKit
import AtollCore
@testable import Atoll

final class WebRuntimeTests: XCTestCase {
    // MARK: - WebContent crash backoff

    func testCrashBackoffStopsAfterRepeatedCrashes() {
        let now = Date()
        // First two crashes within the window still auto-reload.
        XCTAssertTrue(WebViewCoordinator.shouldAutoReload(
            crashTimestamps: [now], now: now, maxCrashes: 3, window: 30))
        XCTAssertTrue(WebViewCoordinator.shouldAutoReload(
            crashTimestamps: [now.addingTimeInterval(-5), now], now: now, maxCrashes: 3, window: 30))
        // Third crash in the window stops the loop (show error page instead).
        XCTAssertFalse(WebViewCoordinator.shouldAutoReload(
            crashTimestamps: [now.addingTimeInterval(-10), now.addingTimeInterval(-5), now],
            now: now, maxCrashes: 3, window: 30))
    }

    func testCrashBackoffIgnoresStaleCrashesOutsideWindow() {
        let now = Date()
        // Two crashes long ago + one now: the old ones fall outside the window,
        // so we still auto-reload.
        XCTAssertTrue(WebViewCoordinator.shouldAutoReload(
            crashTimestamps: [now.addingTimeInterval(-300), now.addingTimeInterval(-120), now],
            now: now, maxCrashes: 3, window: 30))
    }

    func testErrorPageEmbedsEscapedRetryURL() {
        let html = ErrorPage.html(
            title: "Unable to connect",
            message: "The network connection was lost.",
            retryURLString: "https://example.com/a'b\"c"
        )
        XCTAssertTrue(html.contains("The network connection was lost."))
        // Retry target is JSON-encoded so quotes can't break out of the JS string.
        XCTAssertTrue(html.contains(#"https://example.com/a'b\"c"#),
                      "retry URL should be JSON-escaped into the script")
        XCTAssertFalse(html.contains("location.reload()"),
                       "retry must navigate to the real URL, not reload about:blank")
    }

    func testErrorPageWithoutRetryURLHasNoButton() {
        let html = ErrorPage.html(
            title: "Page unavailable", message: "Keeps crashing.", retryURLString: nil)
        XCTAssertFalse(html.contains("<button"))
    }

    // MARK: - Open-external-links-in-app routing

    func testInAppBrowserNeedsOptInAndWebScheme() {
        let web = URL(string: "https://news.example/article")!
        // Opted in, web scheme → in-app window.
        XCTAssertTrue(WebViewCoordinator.shouldOpenInAppBrowser(sourceOptedIn: true, url: web))
        XCTAssertTrue(WebViewCoordinator.shouldOpenInAppBrowser(
            sourceOptedIn: true, url: URL(string: "http://news.example")!))
        XCTAssertTrue(WebViewCoordinator.shouldOpenInAppBrowser(
            sourceOptedIn: true, url: URL(string: "HTTPS://news.example")!))
        // Not opted in → browser, even for a web link.
        XCTAssertFalse(WebViewCoordinator.shouldOpenInAppBrowser(sourceOptedIn: false, url: web))
    }

    func testInAppBrowserNeverTakesNonWebSchemes() {
        // Even opted in, a non-web scheme must not load in an in-app web view: it
        // stays on the openExternally path (mailto reaches Mail, smb/file are
        // dropped by the vetted-scheme gate).
        for other in [
            "mailto:a@example.com",
            "tel:+15551234",
            "smb://attacker.example/share",
            "file:///etc/passwd",
            "someapp://do-something",
        ] {
            XCTAssertFalse(
                WebViewCoordinator.shouldOpenInAppBrowser(sourceOptedIn: true, url: URL(string: other)!),
                "\(other) must not open in an in-app web view")
        }
    }

    func testOpensExternalLinksInAppDefaultsToOff() {
        // A legacy row (nil) keeps opening external links in the system browser.
        XCTAssertFalse(ServiceInstance(label: "S", url: "https://s.example")
            .opensExternalLinksInAppEffective)
        XCTAssertTrue(ServiceInstance(label: "S", url: "https://s.example", openExternalLinksInApp: true)
            .opensExternalLinksInAppEffective)
        XCTAssertFalse(ServiceInstance(label: "S", url: "https://s.example", openExternalLinksInApp: false)
            .opensExternalLinksInAppEffective)
    }

    // MARK: - OS-notification gate + per-service notify flag

    func testOSNotificationGateFiresOnlyWhenEnabledUnmutedAndNotDND() {
        // Fires only when not muted, notifyOS on, and DND off.
        XCTAssertTrue(NotificationManager.shouldPostOSNotification(
            isMuted: false, notifyOS: true, doNotDisturb: false))
        // Each condition independently vetoes.
        XCTAssertFalse(NotificationManager.shouldPostOSNotification(
            isMuted: true, notifyOS: true, doNotDisturb: false), "mute vetoes")
        XCTAssertFalse(NotificationManager.shouldPostOSNotification(
            isMuted: false, notifyOS: false, doNotDisturb: false), "notifyOS off vetoes")
        XCTAssertFalse(NotificationManager.shouldPostOSNotification(
            isMuted: false, notifyOS: true, doNotDisturb: true), "DND vetoes")
    }

    func testNotifiesOSEffectiveDefaultsToEnabledForLegacyRows() {
        let service = ServiceInstance(label: "X", url: "https://x.test")
        // nil (new row, or a row created before the flag existed) → enabled,
        // preserving the prior always-notify behavior.
        XCTAssertNil(service.osNotificationsEnabled)
        XCTAssertTrue(service.notifiesOSEffective)
        // Explicit values are honored.
        service.osNotificationsEnabled = false
        XCTAssertFalse(service.notifiesOSEffective)
        service.osNotificationsEnabled = true
        XCTAssertTrue(service.notifiesOSEffective)
    }

    // MARK: - EmojiPickerView.emojiToPromote

    @MainActor
    func testEmojiToPromotePromotesEmojiFromSearchField() {
        // A single emoji picked from the system Character Viewer lands as the
        // selection rather than a search query.
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "🎉"), "🎉")
        // Skin-tone modifiers, ZWJ sequences, VS16, and flags stay intact.
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "👍🏽"), "👍🏽")
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "👩‍💻"), "👩‍💻")
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "❤️"), "❤️")
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "🇺🇸"), "🇺🇸")
        // Surrounding whitespace is ignored.
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "  🚀 "), "🚀")
        // When several emoji are present, the most recent pick wins.
        XCTAssertEqual(EmojiPickerView.emojiToPromote(from: "😀😃"), "😃")
    }

    @MainActor
    func testEmojiToPromoteLeavesKeywordSearchesAlone() {
        // Ordinary text must keep filtering the grid, not get promoted.
        XCTAssertNil(EmojiPickerView.emojiToPromote(from: "smile"))
        XCTAssertNil(EmojiPickerView.emojiToPromote(from: ""))
        XCTAssertNil(EmojiPickerView.emojiToPromote(from: "   "))
        // Bare digits report isEmoji == true but aren't real emoji.
        XCTAssertNil(EmojiPickerView.emojiToPromote(from: "123"))
        // Mixed text + emoji is treated as a search.
        XCTAssertNil(EmojiPickerView.emojiToPromote(from: "cat 🐱"))
    }

    // MARK: - About: version string

    func testAppVersionStringFormatsShortAndBuild() {
        XCTAssertEqual(
            AppVersion.string(from: ["CFBundleShortVersionString": "1.0.2", "CFBundleVersion": "3"]),
            "Version 1.0.2 (3)"
        )
    }

    func testAppVersionStringFallsBackWhenKeysMissing() {
        XCTAssertEqual(AppVersion.string(from: nil), "Version — (—)")
        XCTAssertEqual(
            AppVersion.string(from: ["CFBundleShortVersionString": "2.0"]),
            "Version 2.0 (—)"
        )
    }

    // MARK: - Custom CSS injection + resolution

    func testCSSInjectionScriptEscapesCSSAndTagsStyle() {
        let css = ".x { content: \"a\"; }\n.y { color: red; }"
        let script = UserScriptManager.makeCSSInjectionScript(css: css)
        // The <style> gets a stable id so re-injection is idempotent.
        XCTAssertTrue(script.contains("atoll-custom-css"))
        // CSS is embedded as a JSON string literal, so the inner quotes are
        // escaped rather than able to break out of the script.
        XCTAssertTrue(script.contains("\\\"a\\\""), "quotes should be JSON-escaped")
        // The raw newline is encoded, so the second rule can't sit on its own
        // line inside the JS source.
        XCTAssertFalse(script.contains("\n.y { color: red; }"), "raw newline must be encoded")
    }

    func testEffectiveCSSPrefersInstanceThenDefaultThenNothing() {
        // No instance CSS → the baked-in default for a known service.
        XCTAssertEqual(
            ServiceCSSDefaults.effectiveCSS(instanceCSS: nil, catalogID: "linkedin"),
            ServiceCSSDefaults.linkedInMessaging
        )
        // An instance override wins over the default.
        XCTAssertEqual(
            ServiceCSSDefaults.effectiveCSS(instanceCSS: "body{}", catalogID: "linkedin"),
            "body{}"
        )
        // A blank override injects nothing — an explicit "no CSS".
        XCTAssertNil(ServiceCSSDefaults.effectiveCSS(instanceCSS: "   ", catalogID: "linkedin"))
        // A service with neither an override nor a default gets nothing.
        XCTAssertNil(ServiceCSSDefaults.effectiveCSS(instanceCSS: nil, catalogID: "slack"))
        XCTAssertNil(ServiceCSSDefaults.effectiveCSS(instanceCSS: nil, catalogID: nil))
    }

    func testLinkedInShipsBakedInMessagingCSS() {
        let css = ServiceCSSDefaults.css(forCatalogID: "linkedin")
        XCTAssertNotNil(css)
        XCTAssertTrue(css?.contains("#global-nav") == true)
        XCTAssertTrue(css?.contains(".scaffold-layout__aside") == true)
    }

    func testServiceInstanceCustomCSSDefaultsNil() {
        let service = ServiceInstance(label: "X", url: "https://x.test", catalogEntryID: "linkedin")
        // A fresh instance carries no override, so it tracks the baked-in default.
        XCTAssertNil(service.customCSS)
    }

    // MARK: - Stay-active / presence

    func testStayActiveDefaultsOff() {
        let service = ServiceInstance(label: "X", url: "https://x.test")
        // Opt-in only: a fresh service never fakes focus.
        XCTAssertFalse(service.staysActiveInBackgroundEffective)
        XCTAssertNil(service.stayActiveInBackground)
    }

    func testStayActiveEffectiveMaterialisesStoredValue() {
        let on = ServiceInstance(label: "X", url: "https://x.test", stayActiveInBackground: true)
        XCTAssertTrue(on.staysActiveInBackgroundEffective)
        let off = ServiceInstance(label: "Y", url: "https://y.test", stayActiveInBackground: false)
        XCTAssertFalse(off.staysActiveInBackgroundEffective)
    }

    @MainActor
    func testFocusOverrideScriptFakesFocusAndSwallowsBlur() {
        let script = UserScriptManager.makeFocusOverrideScript()
        // hasFocus() must report true so a presence check reads active. It's
        // installed by redefining the property, so the name is a quoted literal.
        XCTAssertTrue(script.contains("'hasFocus'"))
        XCTAssertTrue(script.contains("return true"))
        // Blur is swallowed on both window and document, capture phase, so the
        // page's own idle timer never starts.
        XCTAssertTrue(script.contains("stopImmediatePropagation"))
        XCTAssertTrue(script.contains("window.addEventListener('blur'"))
        XCTAssertTrue(script.contains("document.addEventListener('blur'"))
        // Only the top-level window/document blur is swallowed — a form field's
        // own blur (which captures through the same listener) must still reach
        // the page, or dropdowns and draft-saving break.
        XCTAssertTrue(script.contains("e.target === window"))
        XCTAssertTrue(script.contains("e.target === document"))
    }

    func testTeamsIsPresenceSensitiveInCatalog() {
        let catalog = ServiceCatalog.shared
        // Teams broadcasts a status that goes away on blur, so it carries the flag
        // that drives the add-time "always appear active" offer.
        XCTAssertEqual(catalog.entry(for: "teams")?.presenceSensitive, true)
        // A service with no presence status must not carry it (nil, not false).
        XCTAssertNil(catalog.entry(for: "gmail")?.presenceSensitive)
    }

    func testCatalogEntryDecodesWithoutPresenceKey() throws {
        // Entries predating the key must still decode, with presenceSensitive nil.
        let json = """
        [{"id":"x","name":"X","url":"https://x.test","icon":"x","category":"Other","badgeJS":null,"userAgent":null,"description":"d"}]
        """
        let entries = try JSONDecoder().decode([ServiceCatalogEntry].self, from: Data(json.utf8))
        XCTAssertNil(entries[0].presenceSensitive)
    }

    // MARK: - Zoom resolution

    @MainActor
    func testEffectiveZoomPrefersPerServiceThenGlobalDefault() {
        // An explicit per-service zoom wins over the global default.
        XCTAssertEqual(WorkspaceStore.effectiveZoom(pageZoom: 1.25, defaultZoom: 0.9), 1.25)
        // With no per-service zoom, the global default applies.
        XCTAssertEqual(WorkspaceStore.effectiveZoom(pageZoom: nil, defaultZoom: 0.9), 0.9)
        XCTAssertEqual(WorkspaceStore.effectiveZoom(pageZoom: nil, defaultZoom: 1.0), 1.0)
    }

    func testAppPreferencesDefaultZoomEffectiveFallsBackToOne() {
        XCTAssertEqual(AppPreferences().defaultZoomEffective, 1.0)
        XCTAssertEqual(AppPreferences(defaultZoom: 0.8).defaultZoomEffective, 0.8)
    }

    func testGoogleFaviconFallbackIsOffUnlessOptedIn() {
        // A legacy row (nil) must resolve to off: the fallback discloses the
        // service hostname to a third party, so an upgrade shouldn't start
        // doing that without the user asking.
        XCTAssertFalse(AppPreferences().googleFaviconFallbackEnabledEffective)
        XCTAssertTrue(AppPreferences(googleFaviconFallbackEnabled: true)
            .googleFaviconFallbackEnabledEffective)
        XCTAssertFalse(AppPreferences(googleFaviconFallbackEnabled: false)
            .googleFaviconFallbackEnabledEffective)
    }

    func testAutoHibernateDefaultsToOffAndTenMinutes() {
        // Off on a legacy row — an upgrade must not start hibernating services
        // without the user opting in.
        XCTAssertFalse(AppPreferences().autoHibernateIdleEnabledEffective)
        XCTAssertTrue(AppPreferences(autoHibernateIdleEnabled: true)
            .autoHibernateIdleEnabledEffective)
        XCTAssertEqual(AppPreferences().autoHibernateIdleMinutesEffective, 10)
    }

    func testAutoHibernateMinutesClampToSaneRange() {
        // A stored value outside 1...120 is clamped rather than trusted, so a
        // corrupt or hostile row can't set a zero/negative sweep interval.
        XCTAssertEqual(AppPreferences(autoHibernateIdleMinutes: 0).autoHibernateIdleMinutesEffective, 1)
        XCTAssertEqual(AppPreferences(autoHibernateIdleMinutes: -5).autoHibernateIdleMinutesEffective, 1)
        XCTAssertEqual(AppPreferences(autoHibernateIdleMinutes: 5).autoHibernateIdleMinutesEffective, 5)
        XCTAssertEqual(AppPreferences(autoHibernateIdleMinutes: 9999).autoHibernateIdleMinutesEffective, 120)
    }

    func testMessagingServicesAreNotificationCriticalInCatalog() {
        // The auto-hibernation exemption keys off the catalog category, so guard
        // that the messaging apps the user relies on carry it and a heavy
        // non-chat service does not.
        let catalog = ServiceCatalog.shared
        for id in ["slack", "teams", "whatsapp", "discord"] {
            XCTAssertEqual(catalog.entry(for: id)?.category, "Messaging",
                           "\(id) must stay in the Messaging category")
        }
        XCTAssertNotEqual(catalog.entry(for: "spotify")?.category, "Messaging")
    }

    // MARK: - Per-service hibernation policy

    func testHibernationPolicyMigratesLegacyKeepLoaded() {
        // A pre-existing row has no raw policy, only the legacy neverHibernate
        // flag — it must keep behaving as "Keep Loaded" (.never), and an ordinary
        // legacy row must default to following the global setting.
        let kept = ServiceInstance(label: "K", url: "https://k.example", neverHibernate: true)
        XCTAssertEqual(kept.hibernationPolicyEffective, .never)

        let ordinary = ServiceInstance(label: "O", url: "https://o.example", neverHibernate: false)
        XCTAssertEqual(ordinary.hibernationPolicyEffective, .followGlobal)
    }

    func testHibernationPolicyRawWinsOverLegacyFlag() {
        // Once a raw policy is stored it is authoritative, even if the legacy flag
        // disagrees (as it does for .never, which we keep synced to true).
        let immediate = ServiceInstance(
            label: "I", url: "https://i.example",
            neverHibernate: true, hibernationPolicyRaw: HibernationPolicy.immediate.rawValue)
        XCTAssertEqual(immediate.hibernationPolicyEffective, .immediate)

        let after = ServiceInstance(
            label: "A", url: "https://a.example",
            hibernationPolicyRaw: HibernationPolicy.after.rawValue)
        XCTAssertEqual(after.hibernationPolicyEffective, .after)
    }

    func testHibernationPolicyUnknownRawFallsBackToFollowGlobal() {
        // A corrupt or future-written raw value must not crash or silently pin an
        // unexpected behavior — it falls back to following the global setting.
        let svc = ServiceInstance(
            label: "X", url: "https://x.example",
            hibernationPolicyRaw: "nonsense")
        XCTAssertEqual(svc.hibernationPolicyEffective, .followGlobal)
    }

    func testHibernateAfterMinutesClampToSaneRange() {
        // Same guard as the global interval: an out-of-range stored value is
        // clamped, and an unset one defaults to ten minutes.
        XCTAssertEqual(ServiceInstance(label: "S", url: "https://s.example").hibernateAfterMinutesEffective, 10)
        XCTAssertEqual(ServiceInstance(label: "S", url: "https://s.example", hibernateAfterMinutes: 0).hibernateAfterMinutesEffective, 1)
        XCTAssertEqual(ServiceInstance(label: "S", url: "https://s.example", hibernateAfterMinutes: -5).hibernateAfterMinutesEffective, 1)
        XCTAssertEqual(ServiceInstance(label: "S", url: "https://s.example", hibernateAfterMinutes: 45).hibernateAfterMinutesEffective, 45)
        XCTAssertEqual(ServiceInstance(label: "S", url: "https://s.example", hibernateAfterMinutes: 9999).hibernateAfterMinutesEffective, 120)
    }

    func testIsNotificationCriticalByCatalogCategory() {
        // The edit sheet caption and the sweep exemption both read this, so a chat
        // app must report true, a heavy non-chat catalog app false, and a custom
        // (non-catalog) service false — those must use .never instead.
        XCTAssertTrue(ServiceInstance(label: "Slack", url: "https://slack.example", catalogEntryID: "slack").isNotificationCritical)
        XCTAssertFalse(ServiceInstance(label: "Gmail", url: "https://gmail.example", catalogEntryID: "gmail").isNotificationCritical)
        XCTAssertFalse(ServiceInstance(label: "Custom", url: "https://custom.example").isNotificationCritical)
    }

    // MARK: - Dark mode

    func testForceDarkModeDefaultsOff() {
        XCTAssertFalse(ServiceInstance(label: "X", url: "https://x.test").isForceDarkModeEnabled)
        XCTAssertTrue(ServiceInstance(label: "X", url: "https://x.test", forceDarkMode: true).isForceDarkModeEnabled)
        XCTAssertFalse(ServiceInstance(label: "X", url: "https://x.test", forceDarkMode: false).isForceDarkModeEnabled)
    }

    // MARK: - Compatibility fixture boundary

    func testCompatibilityFixtureNeedsItsExactLaunchArgument() {
        XCTAssertFalse(CompatibilityFixture.isEnabled(arguments: []))
        XCTAssertFalse(CompatibilityFixture.isEnabled(arguments: ["--atoll-compatibility"]))
        XCTAssertTrue(CompatibilityFixture.isEnabled(arguments: [CompatibilityFixture.launchArgument]))
    }

    func testCompatibilityFixtureTrustsOnlyLoopbackServerCertificates() {
        let arguments = [CompatibilityFixture.launchArgument]
        XCTAssertTrue(CompatibilityFixture.allowsUntrustedServerCertificate(
            host: "localhost",
            port: 8443,
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            arguments: arguments
        ))
        XCTAssertTrue(CompatibilityFixture.allowsUntrustedServerCertificate(
            host: "127.0.0.1",
            port: 8444,
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            arguments: arguments
        ))
        XCTAssertFalse(CompatibilityFixture.allowsUntrustedServerCertificate(
            host: "example.com",
            port: 8443,
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            arguments: arguments
        ))
        XCTAssertFalse(CompatibilityFixture.allowsUntrustedServerCertificate(
            host: "localhost",
            port: 8443,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
            arguments: arguments
        ))
        XCTAssertFalse(CompatibilityFixture.allowsUntrustedServerCertificate(
            host: "localhost",
            port: 8443,
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            arguments: []
        ))
        XCTAssertFalse(CompatibilityFixture.allowsUntrustedServerCertificate(
            host: "localhost",
            port: 9443,
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            arguments: arguments
        ))
    }

    func testCompatibilityFixtureRecognizesOnlyItsProcessFailureRoute() {
        let arguments = [CompatibilityFixture.launchArgument]
        XCTAssertTrue(CompatibilityFixture.isProcessFailureURL(
            URL(string: "atoll-fixture://web-content-process-failure")!,
            arguments: arguments
        ))
        XCTAssertFalse(CompatibilityFixture.isProcessFailureURL(
            URL(string: "atoll-fixture://another-command")!,
            arguments: arguments
        ))
        XCTAssertFalse(CompatibilityFixture.isProcessFailureURL(
            URL(string: "atoll-fixture://web-content-process-failure/path")!,
            arguments: arguments
        ))
        XCTAssertFalse(CompatibilityFixture.isProcessFailureURL(
            URL(string: "atoll-fixture://web-content-process-failure")!,
            arguments: []
        ))
    }

    // MARK: - Download destination

    func testNonCollidingURLReturnsBaseWhenFree() {
        let dir = URL(fileURLWithPath: "/Users/x/Downloads")
        let url = WebViewCoordinator.nonCollidingURL(in: dir, filename: "a.txt", fileExists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "a.txt")
    }

    func testNonCollidingURLAppendsIndexOnCollision() {
        let dir = URL(fileURLWithPath: "/Users/x/Downloads")
        // "a.txt" and "a (1).txt" are taken; the next free name is "a (2).txt".
        let taken: Set<String> = ["a.txt", "a (1).txt"]
        let url = WebViewCoordinator.nonCollidingURL(
            in: dir,
            filename: "a.txt",
            fileExists: { taken.contains($0.lastPathComponent) }
        )
        XCTAssertEqual(url.lastPathComponent, "a (2).txt")
    }

    func testNonCollidingURLHandlesExtensionlessNames() {
        let dir = URL(fileURLWithPath: "/Users/x/Downloads")
        let taken: Set<String> = ["README"]
        let url = WebViewCoordinator.nonCollidingURL(
            in: dir,
            filename: "README",
            fileExists: { taken.contains($0.lastPathComponent) }
        )
        XCTAssertEqual(url.lastPathComponent, "README (1)")
    }

    func httpResponse(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/file")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func testIsAttachmentDetectsDisposition() {
        XCTAssertTrue(WebViewCoordinator.isAttachment(
            httpResponse(headers: ["Content-Disposition": "attachment; filename=\"report.pdf\""])
        ))
        // Case-insensitive on the header value.
        XCTAssertTrue(WebViewCoordinator.isAttachment(
            httpResponse(headers: ["Content-Disposition": "ATTACHMENT"])
        ))
    }

    func testIsAttachmentFalseForInlineOrMissing() {
        XCTAssertFalse(WebViewCoordinator.isAttachment(
            httpResponse(headers: ["Content-Disposition": "inline"])
        ))
        XCTAssertFalse(WebViewCoordinator.isAttachment(httpResponse(headers: [:])))
        // A non-HTTP response has no headers to inspect.
        let url = URL(string: "https://example.com")!
        XCTAssertFalse(WebViewCoordinator.isAttachment(
            URLResponse(url: url, mimeType: "application/pdf", expectedContentLength: 1, textEncodingName: nil)
        ))
    }

    // MARK: - Passkey notice

    func testNeedsPasskeyNoticeDefaultsTrueForNewService() {
        // A freshly created service has never seen the notice.
        let service = ServiceInstance(label: "Test", url: "https://example.com")
        XCTAssertTrue(service.needsPasskeyNotice)
    }

    func testNeedsPasskeyNoticeFalseOnceSeen() {
        let service = ServiceInstance(label: "Test", url: "https://example.com", hasSeenPasskeyNotice: true)
        XCTAssertFalse(service.needsPasskeyNotice)
    }

    // MARK: - Content blocker

    // MARK: - Web appearance

    func testWebAppearanceTruthTable() {
        XCTAssertTrue(ServiceAppearanceMode.automatic.usesDarkAppearance(shellIsDark: true))
        XCTAssertFalse(ServiceAppearanceMode.automatic.usesDarkAppearance(shellIsDark: false))
        XCTAssertTrue(ServiceAppearanceMode.dark.usesDarkAppearance(shellIsDark: false))
        XCTAssertFalse(ServiceAppearanceMode.light.usesDarkAppearance(shellIsDark: true))

        XCTAssertEqual(
            WebViewPool.webAppearanceName(mode: .automatic, shellIsDark: true),
            .darkAqua
        )
        XCTAssertEqual(
            WebViewPool.webAppearanceName(mode: .automatic, shellIsDark: false),
            .aqua
        )
    }

    @MainActor
    func testNativeWebAppearanceDrivesPrefersColorScheme() async throws {
        let html = """
        <html><body><div role="main">ready</div></body></html>
        """

        let darkWebView = WKWebView(frame: .zero)
        darkWebView.appearance = NSAppearance(named: .darkAqua)
        darkWebView.loadHTMLString(html, baseURL: nil)
        try await waitForFixture(darkWebView)
        let darkMatches = try await darkWebView.evaluateJavaScript(
            "matchMedia('(prefers-color-scheme: dark)').matches"
        ) as? Bool
        XCTAssertEqual(darkMatches, true)

        let lightWebView = WKWebView(frame: .zero)
        lightWebView.appearance = NSAppearance(named: .aqua)
        lightWebView.loadHTMLString(html, baseURL: nil)
        try await waitForFixture(lightWebView)
        let lightMatches = try await lightWebView.evaluateJavaScript(
            "matchMedia('(prefers-color-scheme: dark)').matches"
        ) as? Bool
        XCTAssertEqual(lightMatches, false)
    }

    /// Runs the catalog's Gmail `badgeJS` against a stub Gmail DOM. `hiddenUnread`
    /// models the unread rows Gmail leaves mounted outside the visible list after
    /// you visit another label — the ones that made a document-wide row count read
    /// 99+ over a 2-unread inbox. Returns nil when the expression yields null,
    /// which `pollBadge` treats as "no reading" and never writes.
    func evaluateGmailBadge(
        hash: String,
        ariaLabels: [String],
        visibleUnread: Int,
        hiddenUnread: Int
    ) -> Int? {
        guard let js = ServiceCatalog.shared.entry(for: "gmail")?.badgeJS else {
            XCTFail("Gmail catalog entry should define badgeJS")
            return nil
        }
        guard let context = JSContext() else {
            XCTFail("Could not create a JSContext")
            return nil
        }
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString() ?? "unknown JS exception"
        }
        let labels = (try? String(data: JSONEncoder().encode(ariaLabels), encoding: .utf8) ?? "[]") ?? "[]"
        // The hidden main is listed first on purpose: the expression has to skip a
        // stale container rather than take whichever one comes back first.
        let prelude = """
        var location = { hash: \(jsQuoted(hash)) };
        var aria = \(labels).map(function (l) { return { getAttribute: function () { return l; } }; });
        function rows(n) { var a = []; for (var i = 0; i < n; i++) { a.push({}); } return a; }
        function main(count, visible) {
            return {
                offsetParent: visible ? {} : null,
                querySelectorAll: function (sel) { return sel === 'tr.zA.zE' ? rows(count) : []; }
            };
        }
        var document = { querySelectorAll: function (sel) {
            if (sel === '[aria-label]') { return aria; }
            if (sel === 'div[role=main]') { return [main(\(hiddenUnread), false), main(\(visibleUnread), true)]; }
            if (sel === 'tr.zA.zE') { return rows(\(visibleUnread + hiddenUnread)); }
            return [];
        } };
        """
        let result = context.evaluateScript(prelude + "\n" + js)
        if let jsError { XCTFail("Gmail badgeJS threw: \(jsError)") }
        guard let result, result.isNumber else { return nil }
        return Int(result.toInt32())
    }

    func jsQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    func testGmailBadgeReportsInboxUnreadNotCachedRowsFromOtherLabels() {
        // Gmail keeps a visited label's list mounted after you navigate away, so a
        // document-wide `tr.zA.zE` count kept adding Spam's unread to the badge —
        // measured live as all=101 / visible=2 back in a 2-unread inbox, which the
        // icon showed as 99+. The badge now reads Gmail's own Inbox nav count,
        // which stays put no matter which label is on screen.
        let aria = ["Inbox 2 unread", "Spam 161 unread", "Updates 1987 unread has menu"]

        XCTAssertEqual(
            evaluateGmailBadge(hash: "#inbox", ariaLabels: aria, visibleUnread: 2, hiddenUnread: 99), 2,
            "99 unread rows left over from Spam must not reach the badge"
        )
        XCTAssertEqual(
            evaluateGmailBadge(hash: "#spam", ariaLabels: aria, visibleUnread: 99, hiddenUnread: 2), 2,
            "browsing Spam must not make the badge report Spam's unread"
        )
        XCTAssertEqual(
            evaluateGmailBadge(hash: "#inbox", ariaLabels: ["Inbox 1,987 unread"], visibleUnread: 0, hiddenUnread: 0), 1987,
            "a grouped thousands separator must parse, not truncate to 1"
        )
        // An inbox with nothing unread drops the label's count, and reading that
        // as 0 is what authoritatively clears the badge.
        XCTAssertEqual(
            evaluateGmailBadge(hash: "#inbox", ariaLabels: ["Inbox", "Spam 161 unread"], visibleUnread: 0, hiddenUnread: 99), 0,
            "an empty inbox should clear the badge"
        )
    }

    func testGmailBadgeFallsBackToVisibleRowsAndWithholdsWhenItCannotTell() {
        // If Gmail ever stops labelling the nav item, counting unread rows inside
        // the *visible* list still gets the inbox right — the stale container is
        // excluded by offsetParent.
        XCTAssertEqual(
            evaluateGmailBadge(hash: "#inbox", ariaLabels: [], visibleUnread: 2, hiddenUnread: 99), 2,
            "the fallback must count only the visible list"
        )
        XCTAssertEqual(
            evaluateGmailBadge(hash: "", ariaLabels: [], visibleUnread: 3, hiddenUnread: 50), 3,
            "an empty hash is the inbox too"
        )
        // Outside the inbox with no label to read, the visible list belongs to some
        // other view and counting it would be wrong. Yielding null (not 0) leaves
        // the last good badge alone instead of clearing it.
        XCTAssertNil(
            evaluateGmailBadge(hash: "#spam", ariaLabels: [], visibleUnread: 99, hiddenUnread: 2),
            "with no inbox count available, the badge should go unwritten"
        )
    }

    /// A page shaped like Gmail after you visit Spam and come back: the inbox list
    /// on screen, plus the Spam list still mounted and hidden. `hiddenUnread` rows
    /// are the ones a document-wide count wrongly picked up.
    func fakeGmailHTML(visibleUnread: Int, hiddenUnread: Int, read: Int = 10) -> String {
        func rows(_ unread: Int, read: Int = 0) -> String {
            let unreadRows = (0..<unread).map { _ in "<tr class='zA zE'><td>unread</td></tr>" }
            let readRows = (0..<read).map { _ in "<tr class='zA yO'><td>read</td></tr>" }
            return "<table>" + (unreadRows + readRows).joined() + "</table>"
        }
        return """
        <html><body>
        <div role="navigation">
          <a href="#inbox" aria-label="Inbox \(visibleUnread) unread">Inbox</a>
          <a href="#spam" aria-label="Spam \(hiddenUnread) unread">Spam</a>
        </div>
        <div role="main">\(rows(visibleUnread, read: read))</div>
        <div role="main" style="display:none">\(rows(hiddenUnread))</div>
        </body></html>
        """
    }

    /// Waits for the fixture's own markup, not `document.readyState` — the initial
    /// empty document reads "complete" before `loadHTMLString` has replaced it, so
    /// polling readyState races through and every query comes back empty.
    @MainActor
    func waitForFixture(_ webView: WKWebView) async throws {
        for _ in 0..<100 {
            let mains = try? await webView.evaluateJavaScript("document.querySelectorAll('div[role=main]').length") as? Int
            if let mains, mains > 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Fake Gmail page never finished loading")
    }

    @MainActor
    func testGmailBadgeInRealWebViewIgnoresCachedRowsFromOtherLabels() async throws {
        // The JSC tests above check the expression's logic; this one runs it
        // through the real path — WebKit's engine, the catalog string, and
        // NotificationManager's poll — against a page shaped like the DOM that
        // produced the bug.
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(fakeGmailHTML(visibleUnread: 2, hiddenUnread: 99), baseURL: URL(string: "https://mail.google.com/mail/u/0/#inbox"))
        try await waitForFixture(webView)

        // The fixture reproduces the bug: the old expression still reads 101 here.
        let documentWide = try await webView.evaluateJavaScript("document.querySelectorAll('tr.zA.zE').length") as? Int
        XCTAssertEqual(documentWide, 101, "fixture should hold the 101 unread rows that made the badge read 99+")

        let badgeManager = BadgeManager()
        let notifications = NotificationManager(badgeManager: badgeManager)
        let entry = ServiceCatalog.shared.entry(for: "gmail")
        let serviceID = UUID()
        await notifications.pollNow(for: serviceID, webView: webView, isMuted: false, showBadge: true, catalogEntry: entry)

        XCTAssertEqual(badgeManager.badgeCount(for: serviceID), 2, "the badge should report the inbox's 2, not the page's 101")
    }

    @MainActor
    func testGmailBadgeInRealWebViewWorksInAZeroFrameWebView() async throws {
        // The offscreen badge fetcher builds its web view with a .zero frame, where
        // layout-dependent reads like offsetParent can't be trusted. The nav-label
        // path doesn't touch layout, so a hibernated service still reads its inbox
        // count — worth pinning, because the row-counting fallback would not.
        let webView = WKWebView(frame: .zero)
        webView.loadHTMLString(fakeGmailHTML(visibleUnread: 3, hiddenUnread: 99), baseURL: URL(string: "https://mail.google.com/mail/u/0/#inbox"))
        try await waitForFixture(webView)

        guard let js = ServiceCatalog.shared.entry(for: "gmail")?.badgeJS else {
            return XCTFail("Gmail catalog entry should define badgeJS")
        }
        let count = try await webView.evaluateJavaScript(js) as? Int
        XCTAssertEqual(count, 3, "an offscreen view should still read the inbox count from the nav label")
    }

    func testWebAppearanceMigratesLegacyDarkReaderValues() {
        XCTAssertEqual(
            ServiceInstance(label: "x", url: "https://e.com", darkModeRaw: "off").webAppearance,
            .automatic
        )
        XCTAssertEqual(
            ServiceInstance(label: "x", url: "https://e.com", darkModeRaw: "on").webAppearance,
            .dark
        )
        XCTAssertEqual(
            ServiceInstance(label: "x", url: "https://e.com", forceDarkMode: true).webAppearance,
            .dark
        )
        XCTAssertEqual(
            ServiceInstance(label: "x", url: "https://e.com", darkModeRaw: "auto").webAppearance,
            .automatic
        )
        XCTAssertEqual(
            ServiceInstance(label: "x", url: "https://e.com").webAppearance,
            .automatic
        )
        XCTAssertEqual(
            ServiceInstance(label: "x", url: "https://e.com", darkModeRaw: "light").webAppearance,
            .light
        )
    }

    func testAnnoyanceBlockingDefaultsFalse() {
        XCTAssertFalse(AppPreferences().annoyanceBlockingEnabledEffective)
        XCTAssertTrue(AppPreferences(annoyanceBlockingEnabled: true).annoyanceBlockingEnabledEffective)
    }

    func testContentBlockingEnabledDefaultsTrue() {
        // nil (existing installs / fresh) resolves to enabled.
        XCTAssertTrue(AppPreferences().contentBlockingEnabledEffective)
        XCTAssertFalse(AppPreferences(contentBlockingEnabled: false).contentBlockingEnabledEffective)
    }

    // MARK: - Rail layout preference

    func testRailLayoutParsesFromStoredValueWithSidebarFallback() {
        XCTAssertEqual(AppPreferences(railLayoutRaw: nil).railLayout, .sidebar)
        XCTAssertEqual(AppPreferences(railLayoutRaw: "sidebar").railLayout, .sidebar)
        XCTAssertEqual(AppPreferences(railLayoutRaw: "topBars").railLayout, .topBars)
        XCTAssertEqual(AppPreferences(railLayoutRaw: "garbage").railLayout, .sidebar)
    }

    /// The retired third case maps forward, and it must not take the `.sidebar`
    /// fallback. A `hybrid` user picked their services as tabs along the top; the
    /// fallback would hand them a rail down the left, which is the layout
    /// furthest from what they chose.
    func testRetiredHybridLayoutMapsForwardToTheBarRatherThanTheFallback() {
        XCTAssertEqual(AppPreferences(railLayoutRaw: "hybrid").railLayout, .topBars)
        XCTAssertEqual(RailLayout.resolving("hybrid"), .topBars)
        XCTAssertNotEqual(RailLayout.resolving("hybrid"), .sidebar)
    }

    /// The enum is down to two cases, so the Settings picker offers two. If a
    /// third ever comes back it needs its own forward-map story.
    func testRailLayoutHasExactlyTheTwoSurvivingCases() {
        XCTAssertEqual(RailLayout.allCases.map(\.rawValue), ["sidebar", "topBars"])
        XCTAssertNil(RailLayout(rawValue: RailLayout.retiredHybridRawValue))
    }
}
