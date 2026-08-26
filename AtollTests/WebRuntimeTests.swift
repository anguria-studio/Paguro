import XCTest
import AppKit
import SwiftData
import SQLite3
import JavaScriptCore
import WebKit
@testable import Atoll

extension AtollTests {
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
        let html = WebViewCoordinator.errorPageHTML(
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

    // MARK: - External-open scheme policy

    func testExternalOpenAllowsWebAndCuratedSchemes() {
        for allowed in [
            "https://example.com/a",
            "http://example.com",
            "HTTPS://example.com",  // scheme comparison is case-insensitive
            "mailto:someone@example.com",
            "tel:+15551234",
            "maps://?q=test",
        ] {
            let url = URL(string: allowed)!
            XCTAssertTrue(WebViewCoordinator.isSafeForExternalOpen(url),
                          "\(allowed) should be handed to the system handler")
        }
    }

    func testExternalOpenBlocksCredentialAndFileSchemes() {
        // smb/afp reach a remote share and leak NTLM credentials on click; file
        // and custom schemes hand a page control over local content and other
        // apps. A page can offer any of these as a plain link.
        for blocked in [
            "smb://attacker.example/share",
            "afp://attacker.example/vol",
            "ftp://attacker.example/f",
            "vnc://attacker.example",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "someapp://do-something",
        ] {
            let url = URL(string: blocked)!
            XCTAssertFalse(WebViewCoordinator.isSafeForExternalOpen(url),
                           "\(blocked) must not reach NSWorkspace.open")
        }
    }

    func testErrorPageWithoutRetryURLHasNoButton() {
        let html = WebViewCoordinator.errorPageHTML(
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

    func testShouldStopOutgoingPollReconcilesAgainstPoolActiveID() {
        let outgoing = UUID()
        let incoming = UUID()
        // Normal sidebar switch: the pool still regards the outgoing service as
        // active, so the view layer stops its active poll before the pool
        // downgrades it to background.
        XCTAssertTrue(NotificationManager.shouldStopOutgoingPoll(
            previousID: outgoing, poolActiveID: outgoing))
        // Deep-link switch: AppState already made the incoming service active
        // and moved the outgoing one onto a background poll, so the view layer
        // must NOT stop it (that was the OPEN-ITEMS item 1 race).
        XCTAssertFalse(NotificationManager.shouldStopOutgoingPoll(
            previousID: outgoing, poolActiveID: incoming))
        // No previously displayed service: nothing to stop.
        XCTAssertFalse(NotificationManager.shouldStopOutgoingPoll(
            previousID: nil, poolActiveID: incoming))
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

    func testCatalogEntryDecodesWithoutPresenceKey() {
        // Entries predating the key must still decode, with presenceSensitive nil.
        let json = """
        [{"id":"x","name":"X","url":"https://x.test","icon":"x","category":"Other","badgeJS":null,"userAgent":null,"description":"d"}]
        """.data(using: .utf8)!
        let entries = try! JSONDecoder().decode([ServiceCatalogEntry].self, from: json)
        XCTAssertNil(entries[0].presenceSensitive)
    }

    // MARK: - Zoom resolution

    @MainActor
    func testEffectiveZoomPrefersPerServiceThenGlobalDefault() {
        // An explicit per-service zoom wins over the global default.
        XCTAssertEqual(AppState.effectiveZoom(pageZoom: 1.25, defaultZoom: 0.9), 1.25)
        // With no per-service zoom, the global default applies.
        XCTAssertEqual(AppState.effectiveZoom(pageZoom: nil, defaultZoom: 0.9), 0.9)
        XCTAssertEqual(AppState.effectiveZoom(pageZoom: nil, defaultZoom: 1.0), 1.0)
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

    func testHibernationResolverThresholdPerPolicy() {
        // .never never fires, regardless of the global toggle.
        XCTAssertNil(HibernationResolver.idleThreshold(
            policy: .never, globalEnabled: true, globalIdleMinutes: 30, afterMinutes: 10))
        XCTAssertNil(HibernationResolver.idleThreshold(
            policy: .never, globalEnabled: false, globalIdleMinutes: 30, afterMinutes: 10))

        // .followGlobal uses the global interval only while the global toggle is
        // on; with it off the service must not hibernate on the sweep at all.
        XCTAssertEqual(HibernationResolver.idleThreshold(
            policy: .followGlobal, globalEnabled: true, globalIdleMinutes: 30, afterMinutes: 10), 1800)
        XCTAssertNil(HibernationResolver.idleThreshold(
            policy: .followGlobal, globalEnabled: false, globalIdleMinutes: 30, afterMinutes: 10))

        // .after uses the service's own minutes, independent of the global toggle.
        XCTAssertEqual(HibernationResolver.idleThreshold(
            policy: .after, globalEnabled: false, globalIdleMinutes: 30, afterMinutes: 5), 300)
        XCTAssertEqual(HibernationResolver.idleThreshold(
            policy: .after, globalEnabled: true, globalIdleMinutes: 30, afterMinutes: 45), 2700)

        // .immediate uses the short backstop, whether or not the global toggle is on.
        XCTAssertEqual(HibernationResolver.idleThreshold(
            policy: .immediate, globalEnabled: false, globalIdleMinutes: 30, afterMinutes: 10),
            HibernationResolver.immediateBackstopSeconds)
        XCTAssertEqual(HibernationResolver.idleThreshold(
            policy: .immediate, globalEnabled: true, globalIdleMinutes: 30, afterMinutes: 10),
            HibernationResolver.immediateBackstopSeconds)
    }

    // MARK: - Scheduled DND (quiet hours)

    @MainActor
    func testQuietHoursSameDayWindow() {
        // 09:00–17:00.
        let start = 9 * 60, end = 17 * 60
        XCTAssertTrue(AppState.isWithinQuietHours(nowMinutes: 10 * 60, start: start, end: end))
        XCTAssertFalse(AppState.isWithinQuietHours(nowMinutes: 8 * 60, start: start, end: end))
        XCTAssertTrue(AppState.isWithinQuietHours(nowMinutes: end - 1, start: start, end: end))
        XCTAssertFalse(AppState.isWithinQuietHours(nowMinutes: end, start: start, end: end), "end is exclusive")
        XCTAssertTrue(AppState.isWithinQuietHours(nowMinutes: start, start: start, end: end), "start is inclusive")
    }

    @MainActor
    func testQuietHoursWrapsMidnight() {
        // 22:00–07:00.
        let start = 22 * 60, end = 7 * 60
        XCTAssertTrue(AppState.isWithinQuietHours(nowMinutes: 23 * 60, start: start, end: end))
        XCTAssertTrue(AppState.isWithinQuietHours(nowMinutes: 5 * 60, start: start, end: end))
        XCTAssertFalse(AppState.isWithinQuietHours(nowMinutes: end, start: start, end: end), "end is exclusive")
        XCTAssertTrue(AppState.isWithinQuietHours(nowMinutes: end - 1, start: start, end: end))
        XCTAssertFalse(AppState.isWithinQuietHours(nowMinutes: 20 * 60, start: start, end: end))
    }

    @MainActor
    func testQuietHoursZeroLengthWindowIsNeverActive() {
        XCTAssertFalse(AppState.isWithinQuietHours(nowMinutes: 12 * 60, start: 9 * 60, end: 9 * 60))
    }

    // MARK: - Dark mode

    func testForceDarkModeDefaultsOff() {
        XCTAssertFalse(ServiceInstance(label: "X", url: "https://x.test").isForceDarkModeEnabled)
        XCTAssertTrue(ServiceInstance(label: "X", url: "https://x.test", forceDarkMode: true).isForceDarkModeEnabled)
        XCTAssertFalse(ServiceInstance(label: "X", url: "https://x.test", forceDarkMode: false).isForceDarkModeEnabled)
    }

    // MARK: - Badge sweep sign-in walls (AuthWallResolver)

    func testAuthWallResolverFlagsOffHostFetchWithNoCount() {
        // A session needing interactive sign-in gets redirected to the identity
        // provider and comes back empty. Retrying can't fix it — a transient web
        // view can't sign anyone in — but it does make the provider push another
        // approval request at the user, every sweep.
        XCTAssertTrue(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: "login.microsoftonline.com",
            badge: 0))
    }

    func testAuthWallResolverLeavesHealthyFetchesAlone() {
        // Same host, no count: an authenticated inbox that is simply empty.
        XCTAssertFalse(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: "outlook.cloud.microsoft",
            badge: 0))
        // Redirected but still produced a count, so the session is fine.
        XCTAssertFalse(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: "outlook.office.com",
            badge: 3))
    }

    func testAuthWallResolverTreatsMissingHostAsUnknown() {
        // A load that never resolved a host tells us nothing, and parking on a
        // guess would stop that badge updating until the user opens the service.
        XCTAssertFalse(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft", landedHost: nil, badge: 0))
        XCTAssertFalse(AuthWallResolver.looksLikeSignInWall(
            requestedHost: nil, landedHost: "login.microsoftonline.com", badge: 0))
    }

    // MARK: - Reloading the opener after a popup closes

    func testUserClosingALinkPopupLeavesTheServiceAlone() {
        // The regression this guards: glance at a link opened from a chat
        // service, close the window, and the service used to reload underneath
        // you — losing scroll position and anything typed but not sent.
        XCTAssertFalse(WebViewCoordinator.shouldReloadOpener(
            selfClosed: false, openedAtAuthHost: false))
    }

    func testSelfClosingPopupReloadsTheService() {
        // An OAuth popup finishes by calling window.close(). This is what
        // carries sign-in through providers we don't list by name — a company's
        // own Okta or Keycloak.
        XCTAssertTrue(WebViewCoordinator.shouldReloadOpener(
            selfClosed: true, openedAtAuthHost: false))
    }

    func testHandClosedSignInStillReloadsTheService() {
        // A service asking the user to sign in again opens straight at its
        // provider, so the opening URL is the gateway. Some providers leave the
        // last click to the user, and that flow must still reload.
        XCTAssertTrue(WebViewCoordinator.shouldReloadOpener(
            selfClosed: false, openedAtAuthHost: true))
    }

    func testLinkThatMerelyRedirectsThroughSSOLeavesTheServiceAlone() {
        // Measured on a real machine: opening an Azure portal link from Teams
        // starts at portal.azure.com and redirects through
        // login.microsoftonline.com for SSO. Judging by the navigation chain
        // counted that as a sign-in and reloaded Teams on close. Only the
        // opening URL is consulted, so a link like this stays a link.
        XCTAssertFalse(WebViewCoordinator.isAuthHost("portal.azure.com"))
        XCTAssertFalse(WebViewCoordinator.shouldReloadOpener(
            selfClosed: false, openedAtAuthHost: false))
    }

    func testKnownAuthGatewaysAreRecognisedIncludingSubdomains() {
        XCTAssertTrue(WebViewCoordinator.isAuthHost("login.microsoftonline.com"))
        XCTAssertTrue(WebViewCoordinator.isAuthHost("accounts.google.com"))
        // A subdomain of a gateway still counts.
        XCTAssertTrue(WebViewCoordinator.isAuthHost("eu.login.microsoftonline.com"))
        // An ordinary link target does not.
        XCTAssertFalse(WebViewCoordinator.isAuthHost("teams.cloud.microsoft"))
        XCTAssertFalse(WebViewCoordinator.isAuthHost("example.com"))
    }

    func testAuthPopupClosesAfterItReturnsToTheService() {
        XCTAssertTrue(WebViewCoordinator.shouldCloseAuthPopup(
            openedAtAuthHost: true,
            landedHost: "mail.google.com",
            openerHost: "mail.google.com"
        ))
        XCTAssertTrue(WebViewCoordinator.shouldCloseAuthPopup(
            openedAtAuthHost: true,
            landedHost: "workspace.slack.com",
            openerHost: "app.slack.com"
        ))
        XCTAssertTrue(WebViewCoordinator.shouldCloseAuthPopup(
            openedAtAuthHost: true,
            landedHost: "outlook.cloud.microsoft",
            openerHost: "outlook.cloud.microsoft"
        ))
    }

    func testAuthPopupStaysOpenAtTheIdentityProvider() {
        XCTAssertFalse(WebViewCoordinator.shouldCloseAuthPopup(
            openedAtAuthHost: true,
            landedHost: "accounts.google.com",
            openerHost: "mail.google.com"
        ))
    }

    func testOrdinaryPopupDoesNotCloseWhenItReturnsToTheService() {
        XCTAssertFalse(WebViewCoordinator.shouldCloseAuthPopup(
            openedAtAuthHost: false,
            landedHost: "workspace.slack.com",
            openerHost: "app.slack.com"
        ))
    }

    // MARK: - New-window requests (shouldLoadNewWindowInPlace)

    func testClickedSameServiceLinkLoadsInPlace() {
        // A target=_blank click inside Slack should reuse the service's own web
        // view rather than spawning a window.
        XCTAssertTrue(WebViewCoordinator.shouldLoadNewWindowInPlace(
            navigationType: .linkActivated,
            targetHost: "myteam.slack.com",
            openerHost: "app.slack.com"
        ))
    }

    func testProgrammaticSameServicePopupGetsItsOwnWindow() {
        // A page calling window.open() against its own host must still get a
        // handle back. Collapsing it in place returned nil, which a caller that
        // null-checks the handle reads as a blocked popup — so it gives up
        // silently, with no window and no error to show for it.
        XCTAssertFalse(WebViewCoordinator.shouldLoadNewWindowInPlace(
            navigationType: .other,
            targetHost: "teams.cloud.microsoft",
            openerHost: "teams.cloud.microsoft"
        ))
    }

    func testCrossServicePopupGetsItsOwnWindow() {
        XCTAssertFalse(WebViewCoordinator.shouldLoadNewWindowInPlace(
            navigationType: .linkActivated,
            targetHost: "login.microsoftonline.com",
            openerHost: "teams.cloud.microsoft"
        ))
    }

    func testNewWindowWithUnknownHostIsNotCollapsed() {
        XCTAssertFalse(WebViewCoordinator.shouldLoadNewWindowInPlace(
            navigationType: .linkActivated,
            targetHost: nil,
            openerHost: "app.slack.com"
        ))
        XCTAssertFalse(WebViewCoordinator.shouldLoadNewWindowInPlace(
            navigationType: .linkActivated,
            targetHost: "app.slack.com",
            openerHost: nil
        ))
    }

    // MARK: - Link routing (belongsToService)

    func testBelongsToServiceKeepsSlackWorkspacesInApp() {
        // Same registrable domain, subdomain differs — Slack switching
        // workspaces must stay in-app rather than spawning a new window.
        XCTAssertTrue(WebViewCoordinator.belongsToService("app.slack.com", serviceHost: "app.slack.com"))
        XCTAssertTrue(WebViewCoordinator.belongsToService("myteam.slack.com", serviceHost: "app.slack.com"))
        XCTAssertTrue(WebViewCoordinator.belongsToService("app.slack.com", serviceHost: "myteam.slack.com"))
    }

    func testBelongsToServiceSeparatesGoogleProducts() {
        // Shared-umbrella domain: a Docs/Drive link must NOT be treated as part
        // of the Gmail service (the reported "Google Docs opened in Gmail" bug).
        XCTAssertFalse(WebViewCoordinator.belongsToService("docs.google.com", serviceHost: "mail.google.com"))
        XCTAssertFalse(WebViewCoordinator.belongsToService("drive.google.com", serviceHost: "mail.google.com"))
        // The exact same host is still the same service.
        XCTAssertTrue(WebViewCoordinator.belongsToService("mail.google.com", serviceHost: "mail.google.com"))
        XCTAssertTrue(WebViewCoordinator.belongsToService("docs.google.com", serviceHost: "docs.google.com"))
    }

    func testBelongsToServiceRejectsUnrelatedDomains() {
        XCTAssertFalse(WebViewCoordinator.belongsToService("example.com", serviceHost: "slack.com"))
        XCTAssertFalse(WebViewCoordinator.belongsToService("notion.so", serviceHost: "mail.google.com"))
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

    func testBelongsToServiceIgnoresWWWAndCase() {
        XCTAssertTrue(WebViewCoordinator.belongsToService("www.notion.so", serviceHost: "notion.so"))
        XCTAssertTrue(WebViewCoordinator.belongsToService("APP.SLACK.COM", serviceHost: "app.slack.com"))
    }

    func testBelongsToServiceSeparatesSharedHostingTenants() {
        // Multi-tenant hosting suffixes: each label under the suffix is a
        // DIFFERENT owner, so an attacker sibling must NOT be treated as part of
        // a user's service (which would load its page in the service's
        // authenticated web view). The naive registrable-domain reduction
        // collapsed both to the bare suffix (e.g. "vercel.app") and returned true.
        XCTAssertFalse(WebViewCoordinator.belongsToService("evil.vercel.app", serviceHost: "team.vercel.app"))
        XCTAssertFalse(WebViewCoordinator.belongsToService("attacker.github.io", serviceHost: "myproject.github.io"))
        XCTAssertFalse(WebViewCoordinator.belongsToService("evil.pages.dev", serviceHost: "app.pages.dev"))
        XCTAssertFalse(WebViewCoordinator.belongsToService("evil.workers.dev", serviceHost: "api.workers.dev"))
        // A window.open target on the same tenant is still the same service.
        XCTAssertTrue(WebViewCoordinator.belongsToService("team.vercel.app", serviceHost: "team.vercel.app"))
        XCTAssertTrue(WebViewCoordinator.belongsToService("app.team.vercel.app", serviceHost: "team.vercel.app"))
    }

    func testAuthHostsAreRecognized() {
        // Identity gateways stay in-app so sign-in completes (the reported
        // "Gmail login kicked to the default browser" bug).
        XCTAssertTrue(WebViewCoordinator.isAuthHost("accounts.google.com"))
        XCTAssertTrue(WebViewCoordinator.isAuthHost("login.microsoftonline.com"))
        XCTAssertTrue(WebViewCoordinator.isAuthHost("appleid.apple.com"))
        // Case- and www-insensitive, and subdomains of a gateway still match.
        XCTAssertTrue(WebViewCoordinator.isAuthHost("ACCOUNTS.GOOGLE.COM"))
        XCTAssertTrue(WebViewCoordinator.isAuthHost("eu.login.microsoftonline.com"))
        // Ordinary product hosts are not auth gateways.
        XCTAssertFalse(WebViewCoordinator.isAuthHost("mail.google.com"))
        XCTAssertFalse(WebViewCoordinator.isAuthHost("docs.google.com"))
        XCTAssertFalse(WebViewCoordinator.isAuthHost("example.com"))
    }

    func testAuthHostExemptionLeavesUmbrellaSeparationIntact() {
        // The exemption is layered on top of belongsToService, not baked into
        // it: Google products stay separate for ordinary link routing.
        XCTAssertFalse(WebViewCoordinator.belongsToService("accounts.google.com", serviceHost: "mail.google.com"))
        XCTAssertFalse(WebViewCoordinator.belongsToService("docs.google.com", serviceHost: "mail.google.com"))
    }

    // MARK: - Download destination

    func testSanitizedDownloadFilenameStripsPathParts() {
        // A crafted name must not be able to escape the Downloads folder.
        XCTAssertEqual(WebViewCoordinator.sanitizedDownloadFilename("../../etc/passwd"), "passwd")
        XCTAssertEqual(WebViewCoordinator.sanitizedDownloadFilename("report.pdf"), "report.pdf")
        XCTAssertEqual(WebViewCoordinator.sanitizedDownloadFilename("a/b/c.txt"), "c.txt")
    }

    func testSanitizedDownloadFilenameFallsBackWhenEmpty() {
        XCTAssertEqual(WebViewCoordinator.sanitizedDownloadFilename(""), "download")
        XCTAssertEqual(WebViewCoordinator.sanitizedDownloadFilename("   "), "download")
        XCTAssertEqual(WebViewCoordinator.sanitizedDownloadFilename("/"), "download")
    }

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
    func waitForFixture(_ webView: WKWebView) async throws {
        for _ in 0..<100 {
            let mains = try? await webView.evaluateJavaScript("document.querySelectorAll('div[role=main]').length") as? Int
            if let mains, mains > 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Fake Gmail page never finished loading")
    }

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

    func testBlocklistIdentifierIsStableAndContentAddressed() {
        let a = BlocklistSupport.identifier(prefix: "hz", forJSON: "[1,2,3]")
        let b = BlocklistSupport.identifier(prefix: "hz", forJSON: "[1,2,3]")
        let c = BlocklistSupport.identifier(prefix: "hz", forJSON: "[1,2,4]")
        XCTAssertEqual(a, b)                 // same JSON → same id (cache hit)
        XCTAssertNotEqual(a, c)              // changed JSON → new id (recompile)
        XCTAssertTrue(a.hasPrefix("hz-"))
    }

    func testBlocklistRuleCountAndChunkingGuard() throws {
        let json = "[{\"x\":1},{\"x\":2},{\"x\":3}]"
        XCTAssertEqual(try BlocklistSupport.ruleCount(inJSON: json), 3)
        XCTAssertFalse(BlocklistSupport.needsChunking(count: 3, cap: 5))
        XCTAssertTrue(BlocklistSupport.needsChunking(count: 6, cap: 5))
    }

    func testBlocklistChunkUnderCapReturnsSingle() throws {
        let json = "[{\"x\":1},{\"x\":2}]"
        let chunks = try BlocklistSupport.chunk(json: json, cap: 10)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, json)
    }

    func testBlocklistChunkSplitsOverCapPreservingTotal() throws {
        let rules = (0..<7).map { "{\"x\":\($0)}" }.joined(separator: ",")
        let json = "[\(rules)]"
        let chunks = try BlocklistSupport.chunk(json: json, cap: 3)
        XCTAssertEqual(chunks.count, 3)  // 3 + 3 + 1
        let total = try chunks.reduce(0) { $0 + (try BlocklistSupport.ruleCount(inJSON: $1)) }
        XCTAssertEqual(total, 7)
    }

    func testBlocklistChunkRejectsNonArray() {
        XCTAssertThrowsError(try BlocklistSupport.chunk(json: "{\"not\":\"an array\"}"))
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
