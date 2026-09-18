import Foundation
import WebKit

@MainActor
final class UserScriptManager {
    private var messageHandlers: [UUID: NotificationMessageHandler] = [:]
    private let islandPanelController: IslandPanelController?
    private let notificationProbeEnabled: Bool

    var isServiceMuted: (@MainActor (UUID) -> Bool)?
    var notificationLockSnapshot = AtomicBool(false)
    /// Per-service "forward notifications to macOS" flag. Defaults to true when
    /// unset, preserving behavior for services that predate the toggle.
    var isServiceNotifyingOS: (@MainActor (UUID) -> Bool)?
    var isSystemNotificationsEnabled: (@MainActor () -> Bool)?
    var isIslandNotificationsEnabled: (@MainActor (UUID) -> Bool)?
    var isDoNotDisturbActive: (@MainActor () -> Bool)?
    var autoDismissCookieBanners = AppPreferenceDefaults.autoDismissCookieBanners

    init(
        islandPanelController: IslandPanelController? = nil,
        notificationProbeEnabled: Bool = NotificationProbeConfiguration.isEnabled()
    ) {
        self.islandPanelController = islandPanelController
        self.notificationProbeEnabled = notificationProbeEnabled
    }

    /// Full setup for a freshly built web view: the message handlers (added once)
    /// plus all user scripts.
    func configureScripts(
        for instance: ServiceInstance,
        customCSS: String?,
        stayActiveInBackground: Bool,
        on controller: WKUserContentController
    ) {
        installHandlers(for: instance, on: controller)
        installUserScripts(
            for: instance,
            customCSS: customCSS,
            stayActiveInBackground: stayActiveInBackground,
            on: controller
        )
    }

    /// Registers the message handlers. Called once when the web view is built —
    /// NOT on reinstall, since `removeAllUserScripts()` leaves message handlers in
    /// place and re-adding would throw.
    func installHandlers(for instance: ServiceInstance, on controller: WKUserContentController) {
        let mutedCheck = isServiceMuted
        let lockSnapshot = notificationLockSnapshot
        let notifyOSCheck = isServiceNotifyingOS
        let systemCheck = isSystemNotificationsEnabled
        let islandCheck = isIslandNotificationsEnabled
        let dndCheck = isDoNotDisturbActive
        // The favicon can arrive after this web view opens. Read the saved icon
        // for each new notification, as the sidebar does, rather than freezing nil.
        let serviceIconURLProvider: @MainActor () -> URL? = {
            NotificationAttachmentStore.prepareServiceIcon(for: instance)
        }
        let presenter = NotificationPresenter(
            serviceLabel: instance.label,
            serviceIconURLProvider: serviceIconURLProvider,
            lockSnapshot: lockSnapshot
        )
        let islandPresenter = islandPanelController.map { controller in
            IslandNotificationPresenter(
                controller: controller,
                serviceLabel: instance.label,
                serviceIconURLProvider: serviceIconURLProvider
            )
        }
        let presentationRouter = NotificationPresentationRouter(
            systemPresenter: presenter,
            isLockedCheck: { lockSnapshot.value },
            islandPresenter: islandPresenter,
            isMutedCheck: { id in
                mutedCheck?(id) ?? false
            },
            isSystemEnabledCheck: { id in
                (systemCheck?() ?? true) && (notifyOSCheck?(id) ?? true)
            },
            isIslandEnabledCheck: { id in
                islandCheck?(id) ?? false
            },
            isIslandAvailableCheck: {
                [weak islandPanelController = islandPanelController] in
                islandPanelController?.canPresentIsland ?? false
            },
            isDoNotDisturbCheck: {
                dndCheck?() ?? false
            }
        )
        // Read the address for each event. A service edit can make a target
        // that was safe for the old address unsafe for the current account.
        let handler = NotificationMessageHandler(
            serviceID: instance.id,
            serviceURLProvider: { URL(string: instance.url) },
            presentationRouter: presentationRouter,
            probeEnabled: notificationProbeEnabled,
            probeServiceKind: instance.catalogEntryID.flatMap {
                ServiceCatalog.shared.entry(for: $0)?.id
            } ?? "custom"
        )
        controller.add(handler, name: "paguroNotification")
        messageHandlers[instance.id] = handler
    }

    /// Adds all user scripts. Safe to call again after `removeAllUserScripts()`
    /// when an injected service option changes.
    func installUserScripts(
        for instance: ServiceInstance,
        customCSS: String?,
        stayActiveInBackground: Bool,
        on controller: WKUserContentController
    ) {
        let notificationScript = makeNotificationInterceptionScript()
        let userScript = WKUserScript(
            source: notificationScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(userScript)

        // Page Visibility override — makes preloaded/off-screen views report as
        // "visible" so services that only write their unread count into the
        // title while visible (WhatsApp, Messenger, Discord, …) still surface it
        // for the badge. Focus is intentionally left untouched.
        let visibilityScript = WKUserScript(
            source: Self.makeVisibilityOverrideScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(visibilityScript)

        // Focus override (opt-in per service) — reports the page as focused even
        // while Paguro is in the background, so a service that flips presence to
        // "away" on window blur (Microsoft Teams) keeps showing the user active.
        // Off unless the service opted in, because faking focus can make a site
        // hold back the notifications Paguro forwards.
        if stayActiveInBackground {
            let focusScript = WKUserScript(
                source: Self.makeFocusOverrideScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            controller.addUserScript(focusScript)
        }

        // WebRTC call detection — hooks RTCPeerConnection to track active calls
        let callDetectionScript = WKUserScript(
            source: Self.makeCallDetectionScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(callDetectionScript)

        // Media registry — records the elements the page plays, so the pool can
        // ask whether any of them is audible. Same frames as the Web Audio mute
        // script, because a voice message can play inside a frame.
        let mediaRegistryScript = WKUserScript(
            source: Self.makeAudibleMediaRegistryScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(mediaRegistryScript)

        if autoDismissCookieBanners {
            let cookieScript = WKUserScript(
                source: CookieConsentManager.makeConsentDismissalScript(),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            controller.addUserScript(cookieScript)
        }

        // Per-service custom CSS (e.g. LinkedIn's messaging-only view). Injected
        // at document start so the page never flashes its unstyled layout, and
        // only when there's actually CSS to apply.
        if let customCSS, !customCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cssScript = WKUserScript(
                source: Self.makeCSSInjectionScript(css: customCSS),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            controller.addUserScript(cssScript)
        }

    }

    /// Builds a script that injects `css` into the page as a `<style>` element.
    /// The CSS is JSON-encoded into a JS string literal so quotes, newlines, and
    /// backslashes can't break out of the script. The style node carries a stable
    /// id and is reused if already present, so re-injection can never stack.
    nonisolated static func makeCSSInjectionScript(css: String) -> String {
        let literal: String
        if let data = try? JSONEncoder().encode(css),
           let json = String(data: data, encoding: .utf8) {
            literal = json
        } else {
            // Encoding a String basically never fails, but if it did we'd inject
            // an empty style and silently lose the user's CSS — log so it isn't
            // a mystery.
            AppLogger.general.warning("Custom CSS could not be JSON-encoded; injecting no CSS for this service")
            literal = "\"\""
        }
        return """
        (function() {
            var CSS = \(literal);
            var existing = document.getElementById('paguro-custom-css');
            if (existing) { existing.textContent = CSS; return; }
            var style = document.createElement('style');
            style.id = 'paguro-custom-css';
            style.textContent = CSS;
            (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    func removeHandler(for instanceID: UUID) {
        messageHandlers.removeValue(forKey: instanceID)
    }

    /// JavaScript that can be evaluated to check if a WebRTC call is active.
    /// Returns `true` if any RTCPeerConnection is in a connected/active state.
    nonisolated static let callDetectionQueryJS = "window.__paguroActiveCall === true"

    /// The name of the page-side registry of media elements that play. It is
    /// long and prefixed, so a page is unlikely to hold the same name, and the
    /// registry is defined as a non-enumerable property, so a page that lists
    /// the properties of `window` does not see it.
    nonisolated static let mediaRegistryName = "__paguroPlayingMedia"

    /// Records each media element that the page plays.
    ///
    /// `document.querySelectorAll('audio,video')` reports only the elements in
    /// the document. Many web apps play a voice message or an alert sound
    /// through `new Audio()`, which never enters the document, so the registry
    /// is the only public way to see those elements. It wraps
    /// `HTMLMediaElement.prototype.play` and holds the element until it stops.
    ///
    /// The registry holds strong references, so listeners for `pause`, `ended`,
    /// and `emptied` remove the element again. A finished element that the page
    /// no longer holds can then be collected.
    ///
    /// The wrapper calls the original `play` and returns its result unchanged,
    /// so page behavior does not change. Every step runs inside `try`, so an
    /// unusual or hostile page cannot break the page or the probe.
    static func makeAudibleMediaRegistryScript() -> String {
        return """
        (function() {
            try {
                var Media = window.HTMLMediaElement;
                if (!Media || !Media.prototype || !window.Set || !window.WeakSet) return;
                if (window.\(mediaRegistryName)) return;
                var playing = new Set();
                Object.defineProperty(window, '\(mediaRegistryName)', {
                    value: playing,
                    configurable: false,
                    enumerable: false,
                    writable: false
                });
                // One shared listener for every element, so the registry adds no
                // closure for each element it watches.
                var forget = function(event) {
                    try { playing.delete(event.target); } catch (e) {}
                };
                var watched = new WeakSet();
                var play = Media.prototype.play;
                Media.prototype.play = function() {
                    try {
                        if (!watched.has(this)) {
                            watched.add(this);
                            this.addEventListener('pause', forget);
                            this.addEventListener('ended', forget);
                            this.addEventListener('emptied', forget);
                        }
                        playing.add(this);
                    } catch (e) {}
                    return play.apply(this, arguments);
                };
            } catch (e) {}
        })();
        """
    }

    /// JavaScript that reports what the page plays: how many media elements it
    /// holds, how many of them are audible now, how many Web Audio contexts the
    /// mute guard measures, and whether their output carried a signal recently.
    ///
    /// The result is `{elements, audible, contexts, signal}`, or `null` when the
    /// page cannot answer. The pool grants background audio when `audible` is
    /// above zero or `signal` is true; it reports every fact in one log line, so
    /// the reason for a decision is visible in the console. No address, title,
    /// or media source leaves the page.
    ///
    /// An element counts as audible when it is not paused, not ended, has data
    /// to play, is not muted, has a volume above zero, and carries sound. The
    /// last test uses what WebKit exposes to a page: decoded audio bytes, then
    /// the audio track list, and an unmuted `<video>` that plays counts as
    /// audible when the page reports neither. A muted looping video — a
    /// sticker, an avatar, a GIF — therefore counts as silent.
    ///
    /// The second source covers a page that plays sound with no media element.
    /// WhatsApp Web decodes a voice message itself and sends it to the speakers
    /// through the Web Audio API, so no element exists to read, not even a
    /// detached one. `WebAudioMuteScript` measures the level that each context
    /// sends to its destination and records when it last carried sound. A
    /// running context alone still grants nothing: WhatsApp Web and Telegram Web
    /// both keep a silent context while idle.
    ///
    /// Elements come from the registry and from the document, so media that
    /// started before the registry saw it is still found. Same-origin frames
    /// answer as well, for the elements and for the Web Audio measurement. A
    /// cross-origin frame denies every read, and the probe skips it.
    nonisolated static let audibleMediaQueryJS = """
    (function() {
        // How long a measured Web Audio signal still counts. Speech has gaps
        // between two words, and a background page throttles its timers to about
        // one tick per second, so a shorter window would report silence in the
        // middle of a voice message. The exemption itself lives far longer: the
        // pool polls every 5 seconds and holds a 90 second grace period, so this
        // window decides only whether one answer says "sound now".
        var signalWindow = 2000;
        function readWebAudio(view, counts) {
            try {
                var read = view.\(WebAudioMuteScript.stateReaderName);
                if (typeof read !== 'function') return;
                var report = read();
                if (!report) return;
                if (typeof report.running === 'number') counts.contexts += report.running;
                if (typeof report.since === 'number' &&
                    report.since >= 0 && report.since <= signalWindow) {
                    counts.signal = true;
                }
            } catch (e) {}
        }
        function hasSound(element) {
            // WebKit reports the decoded audio bytes of an element that carries
            // sound. A silent video decodes none of them.
            if (typeof element.webkitAudioDecodedByteCount === 'number') {
                return element.webkitAudioDecodedByteCount > 0;
            }
            if (element.audioTracks) return element.audioTracks.length > 0;
            // The page reports neither, so an unmuted element that plays counts.
            return true;
        }
        function isAudible(element) {
            try {
                if (element.paused || element.ended) return false;
                if (!(element.readyState > 2)) return false;
                if (element.muted || !(element.volume > 0)) return false;
                // An audio element carries sound by definition. The tag name
                // holds in every frame, which `instanceof` does not.
                if (String(element.tagName).toUpperCase() === 'AUDIO') return true;
                return hasSound(element);
            } catch (e) {
                return false;
            }
        }
        function collect(view, counts, depth) {
            var media = new Set();
            var registry = view.\(mediaRegistryName);
            if (registry && typeof registry.forEach === 'function') {
                registry.forEach(function(element) {
                    try {
                        // A refused `play` leaves a paused element behind, and
                        // no event follows it. Drop those here as well, so the
                        // registry cannot grow without an end.
                        if (element.paused || element.ended) registry.delete(element);
                        else media.add(element);
                    } catch (e) {}
                });
            }
            var attached = view.document.querySelectorAll('audio,video');
            for (var i = 0; i < attached.length; i++) media.add(attached[i]);
            media.forEach(function(element) {
                counts.elements++;
                if (isAudible(element)) counts.audible++;
            });
            readWebAudio(view, counts);
            if (depth >= 4) return;
            for (var j = 0; j < view.frames.length; j++) {
                try { collect(view.frames[j], counts, depth + 1); } catch (e) {}
            }
        }
        try {
            var counts = {elements: 0, audible: 0, contexts: 0, signal: false};
            collect(window, counts, 0);
            return counts;
        } catch (e) {
            return null;
        }
    })()
    """

    /// Reports the page as visible even when its web view is preloaded/off-screen,
    /// so services that gate their unread-count title updates on Page Visibility
    /// (WhatsApp, Messenger, Discord, …) still surface the count for the badge.
    ///
    /// Deliberately does NOT fake `document.hasFocus()` — it stays false for a
    /// background view — so apps that gate desktop notifications on *focus* keep
    /// firing them, preserving Paguro's `window.Notification` forwarding.
    static func makeVisibilityOverrideScript() -> String {
        return """
        (function() {
            try {
                Object.defineProperty(document, 'visibilityState', {
                    configurable: true,
                    get: function() { return 'visible'; }
                });
                Object.defineProperty(document, 'hidden', {
                    configurable: true,
                    get: function() { return false; }
                });
                // Swallow real visibilitychange events so a page can't react to
                // the view actually going off-screen and revert to "hidden"
                // behavior; the overridden getters keep reporting visible.
                document.addEventListener('visibilitychange', function(e) {
                    e.stopImmediatePropagation();
                }, true);
            } catch (e) {}
        })();
        """
    }

    /// Reports the page as focused even when its web view is in the background,
    /// so a service that flips your status to "away"/"idle" on window blur
    /// (Microsoft Teams) keeps showing you active. Opt-in per service — see
    /// `ServiceInstance.stayActiveInBackground`.
    ///
    /// Overrides `document.hasFocus()` to true and swallows real `blur` events on
    /// both window and document (capture phase, before the page's own handlers)
    /// so a page can't start its idle timer when Paguro loses focus. Pairs with
    /// the always-visible override so both halves of the "is the user here?"
    /// check read active.
    static func makeFocusOverrideScript() -> String {
        return """
        (function() {
            try {
                Object.defineProperty(document, 'hasFocus', {
                    configurable: true,
                    value: function() { return true; }
                });
                // Swallow ONLY the top-level blur that fires when the whole
                // window/document loses focus (the app going to the background).
                // A form field losing focus fires its own blur that captures
                // down through this same window listener; killing those too would
                // break dropdowns, draft saving, and validation across the page,
                // so guard on the event target being the window or document.
                var swallow = function(e) {
                    if (e.target === window || e.target === document) {
                        e.stopImmediatePropagation();
                    }
                };
                window.addEventListener('blur', swallow, true);
                document.addEventListener('blur', swallow, true);
            } catch (e) {}
        })();
        """
    }

    /// Hooks RTCPeerConnection to detect active voice/video calls.
    /// Sets `window.__paguroActiveCall = true` when a connection is active,
    /// and `false` when all connections close.
    private static func makeCallDetectionScript() -> String {
        return """
        (function() {
            if (!window.RTCPeerConnection) return;

            var OrigRTC = window.RTCPeerConnection;
            var activePeers = new Set();
            var frameId = Math.random().toString(36).substr(2, 9);

            window.__paguroActiveCall = false;

            // Aggregate call state onto the top frame, keyed by frame, so a call
            // running inside a same-origin iframe is still seen by the pool's
            // main-frame check (evaluateJavaScript runs in the main frame only).
            // Cross-origin frames can't reach window.top (property access
            // throws), so they fall back to their own flag — an inherent limit.
            function updateCallState() {
                var active = activePeers.size > 0;
                try {
                    var top = window.top || window;
                    if (!top.__paguroCallFrames) top.__paguroCallFrames = {};
                    if (active) {
                        top.__paguroCallFrames[frameId] = true;
                    } else {
                        delete top.__paguroCallFrames[frameId];
                    }
                    top.__paguroActiveCall = Object.keys(top.__paguroCallFrames).length > 0;
                } catch (e) {
                    window.__paguroActiveCall = active;
                }
            }

            window.RTCPeerConnection = function() {
                var pc = new (Function.prototype.bind.apply(OrigRTC, [null].concat(Array.from(arguments))))();
                var id = Math.random().toString(36).substr(2, 9);

                pc.addEventListener('connectionstatechange', function() {
                    if (pc.connectionState === 'connected') {
                        activePeers.add(id);
                    } else if (pc.connectionState === 'closed' ||
                               pc.connectionState === 'failed' ||
                               pc.connectionState === 'disconnected') {
                        activePeers.delete(id);
                    }
                    updateCallState();
                });

                pc.addEventListener('iceconnectionstatechange', function() {
                    if (pc.iceConnectionState === 'connected' ||
                        pc.iceConnectionState === 'completed') {
                        activePeers.add(id);
                    } else if (pc.iceConnectionState === 'closed' ||
                               pc.iceConnectionState === 'failed' ||
                               pc.iceConnectionState === 'disconnected') {
                        activePeers.delete(id);
                    }
                    updateCallState();
                });

                return pc;
            };

            window.RTCPeerConnection.prototype = OrigRTC.prototype;
            Object.keys(OrigRTC).forEach(function(key) {
                window.RTCPeerConnection[key] = OrigRTC[key];
            });
        })();
        """
    }

    /// Intercepts the two ways a page raises a notification and forwards each to
    /// the native handler.
    ///
    /// The replacement has to keep the `Notification` contract intact, which the
    /// first version of this script did not. It assigned a bare function over
    /// `window.Notification` without carrying `prototype` or the statics across,
    /// so `n instanceof Notification` was false and everything on the
    /// constructor except the two properties re-declared here disappeared — a
    /// site that feature-detects either way saw a broken API. The
    /// `RTCPeerConnection` shim in this same file already does both; this now
    /// matches it.
    ///
    /// `ServiceWorkerRegistration.prototype.showNotification` is the other path,
    /// and it was not covered at all. Modern web apps raise notifications
    /// through it rather than through `new Notification`, so those never reached
    /// Paguro. **This covers the page-side call only.** A notification raised
    /// from inside the service worker — the push path — runs in a worker context
    /// no page script can enter, and is still not intercepted.
    ///
    /// The original constructor is still called so the page gets a real
    /// `Notification` back to hold `onclick`/`close()` on. That cannot double up
    /// today: WebKit only delivers web notifications to an app that adopts the
    /// `WKUIDelegate` notification methods, and Paguro adopts none of them, so
    /// the original object is inert for display.
    private func makeNotificationInterceptionScript() -> String {
        #if DEBUG
        let probeEnabled = notificationProbeEnabled ? "true" : "false"
        let probeSupport = """
            // Report structure only. Values, lengths, and message text do not
            // enter the probe output.
            function notificationDataShape(value, depth, seen) {
                try {
                    if (value === undefined) return 'missing';
                    if (value === null) return 'null';
                    if (Array.isArray(value)) return 'array';
                    var kind = typeof value;
                    if (kind !== 'object') {
                        return kind === 'string' || kind === 'number' ||
                            kind === 'boolean' ? kind : 'other';
                    }
                    if (depth >= 2) return 'object';
                    if (seen.indexOf(value) !== -1) return 'object(cycle)';
                    seen.push(value);
                    var keys = Object.keys(value).sort();
                    var fields = [];
                    for (var i = 0; i < keys.length && i < 16; i++) {
                        var key = keys[i];
                        var safeKey = /^[A-Za-z_$][A-Za-z0-9_$.-]{0,63}$/.test(key)
                            ? key : '<redacted-key>';
                        var fieldShape = 'unavailable';
                        try {
                            fieldShape = notificationDataShape(value[key], depth + 1, seen);
                        } catch (e) {}
                        fields.push(safeKey + ':' + fieldShape);
                    }
                    if (keys.length > 16) fields.push('<more>');
                    seen.pop();
                    return '{' + fields.join(',') + '}';
                } catch (e) {
                    return 'unavailable';
                }
            }
        """
        let probePayload = """
                    if (probeEnabled) {
                        payload.probe = {
                            source: source,
                            dataShape: notificationDataShape(
                                options ? options.data : undefined,
                                0,
                                []
                            )
                        };
                    }
        """
        #else
        let probeEnabled = "false"
        let probeSupport = ""
        let probePayload = ""
        #endif
        return """
        (function() {
            var probeEnabled = \(probeEnabled);

            // The current page can show a different conversation. Use only a
            // destination that the notification supplies.
            function notificationTarget(options) {
                if (!options) return '';
                var data = options.data;
                if (typeof data === 'string') return data;
                if (!data || typeof data !== 'object') return '';
                var keys = ['targetURL', 'url', 'href'];
                for (var i = 0; i < keys.length; i++) {
                    var value = data[keys[i]];
                    if (typeof value === 'string') return value;
                }
                return '';
            }

            \(probeSupport)

            var notificationClicks = new Map();
            var maximumNotificationClicks = 128;

            function makeNotificationClickToken() {
                try {
                    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
                        return window.crypto.randomUUID();
                    }
                } catch (e) {}
                return '';
            }

            function retainNotificationClick(token, notification) {
                if (!token || typeof token !== 'string') return;
                var entry = {
                    notification: notification,
                    hasClickListener: false
                };
                var originalAddEventListener = notification.addEventListener;
                if (typeof originalAddEventListener === 'function') {
                    try {
                        notification.addEventListener = function(type) {
                            if (type === 'click') entry.hasClickListener = true;
                            return originalAddEventListener.apply(this, arguments);
                        };
                    } catch (e) {}
                }
                while (notificationClicks.size >= maximumNotificationClicks) {
                    var oldest = notificationClicks.keys().next().value;
                    notificationClicks.delete(oldest);
                }
                notificationClicks.set(token.toLowerCase(), entry);
            }

            Object.defineProperty(window, '__paguroDispatchNotificationClick', {
                value: function(token) {
                    if (!token || typeof token !== 'string') return false;
                    var normalizedToken = token.toLowerCase();
                    var entry = notificationClicks.get(normalizedToken);
                    if (!entry) return false;
                    notificationClicks.delete(normalizedToken);
                    var notification = entry.notification;
                    var hasClickHandler = entry.hasClickListener ||
                        typeof notification.onclick === 'function';
                    try {
                        notification.dispatchEvent(new Event('click'));
                        return hasClickHandler;
                    } catch (e) {
                        return false;
                    }
                },
                configurable: false,
                enumerable: false,
                writable: false
            });

            function forward(title, options, source, pageClickToken) {
                try {
                    var payload = {
                        version: 1,
                        type: 'web-notification',
                        title: title == null ? '' : String(title),
                        body: (options && options.body) || '',
                        tag: (options && options.tag) || '',
                        targetURL: notificationTarget(options),
                        pageClickToken: pageClickToken || ''
                    };
            \(probePayload)
                    window.webkit.messageHandlers.paguroNotification.postMessage(
                        JSON.stringify(payload)
                    );
                } catch (e) {
                    // A page that has torn down the bridge must not take the
                    // site's own notification call down with it.
                }
            }

            var OrigNotification = window.Notification;
            if (OrigNotification) {
                var PaguroNotification = function(title, options) {
                    var notification = new OrigNotification(title, options);
                    var pageClickToken = makeNotificationClickToken();
                    retainNotificationClick(pageClickToken, notification);
                    forward(title, options, 'constructor', pageClickToken);
                    return notification;
                };

                // Same prototype object, so `instanceof Notification` holds for
                // instances the original constructor returns.
                PaguroNotification.prototype = OrigNotification.prototype;

                // Carry every static across, descriptors and all, before the two
                // overrides below replace the ones Paguro answers itself.
                Object.getOwnPropertyNames(OrigNotification).forEach(function(key) {
                    if (key === 'prototype' || key === 'name' || key === 'length') return;
                    try {
                        var descriptor = Object.getOwnPropertyDescriptor(OrigNotification, key);
                        if (descriptor) Object.defineProperty(PaguroNotification, key, descriptor);
                    } catch (e) {}
                });

                Object.defineProperty(PaguroNotification, 'permission', {
                    get: function() { return 'granted'; },
                    configurable: true
                });
                PaguroNotification.requestPermission = function(cb) {
                    if (cb) cb('granted');
                    return Promise.resolve('granted');
                };

                window.Notification = PaguroNotification;
            }

            if (window.ServiceWorkerRegistration &&
                window.ServiceWorkerRegistration.prototype &&
                window.ServiceWorkerRegistration.prototype.showNotification) {
                var origShow = window.ServiceWorkerRegistration.prototype.showNotification;
                window.ServiceWorkerRegistration.prototype.showNotification = function(title, options) {
                    forward(title, options, 'service-worker-registration', '');
                    return origShow.apply(this, arguments);
                };
            }
        })();
        """
    }
}
