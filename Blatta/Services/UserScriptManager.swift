import Foundation
import WebKit

@MainActor
final class UserScriptManager {
    private var messageHandlers: [UUID: NotificationMessageHandler] = [:]
    private let islandPanelController: IslandPanelController?

    var isServiceMuted: (@MainActor (UUID) -> Bool)?
    var notificationLockSnapshot = AtomicBool(false)
    /// Per-service "forward notifications to macOS" flag. Defaults to true when
    /// unset, preserving behavior for services that predate the toggle.
    var isServiceNotifyingOS: (@MainActor (UUID) -> Bool)?
    var isSystemNotificationsEnabled: (@MainActor () -> Bool)?
    var isIslandNotificationsEnabled: (@MainActor (UUID) -> Bool)?
    var isDoNotDisturbActive: (@MainActor () -> Bool)?
    var autoDismissCookieBanners = AppPreferenceDefaults.autoDismissCookieBanners

    init(islandPanelController: IslandPanelController? = nil) {
        self.islandPanelController = islandPanelController
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
        let serviceIconURL = NotificationAttachmentStore.prepareServiceIcon(for: instance)
        let presenter = NotificationPresenter(
            serviceLabel: instance.label,
            serviceIconURL: serviceIconURL,
            lockSnapshot: lockSnapshot
        )
        let islandPresenter = islandPanelController.map { controller in
            IslandNotificationPresenter(
                controller: controller,
                serviceLabel: instance.label,
                serviceIconURL: serviceIconURL
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
        let handler = NotificationMessageHandler(
            serviceID: instance.id,
            presentationRouter: presentationRouter
        )
        controller.add(handler, name: "blattaNotification")
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
        // while Blatta is in the background, so a service that flips presence to
        // "away" on window blur (Microsoft Teams) keeps showing the user active.
        // Off unless the service opted in, because faking focus can make a site
        // hold back the notifications Blatta forwards.
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
            var existing = document.getElementById('blatta-custom-css');
            if (existing) { existing.textContent = CSS; return; }
            var style = document.createElement('style');
            style.id = 'blatta-custom-css';
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
    nonisolated static let callDetectionQueryJS = "window.__blattaActiveCall === true"

    /// Reports the page as visible even when its web view is preloaded/off-screen,
    /// so services that gate their unread-count title updates on Page Visibility
    /// (WhatsApp, Messenger, Discord, …) still surface the count for the badge.
    ///
    /// Deliberately does NOT fake `document.hasFocus()` — it stays false for a
    /// background view — so apps that gate desktop notifications on *focus* keep
    /// firing them, preserving Blatta's `window.Notification` forwarding.
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
    /// so a page can't start its idle timer when Blatta loses focus. Pairs with
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
    /// Sets `window.__blattaActiveCall = true` when a connection is active,
    /// and `false` when all connections close.
    private static func makeCallDetectionScript() -> String {
        return """
        (function() {
            if (!window.RTCPeerConnection) return;

            var OrigRTC = window.RTCPeerConnection;
            var activePeers = new Set();
            var frameId = Math.random().toString(36).substr(2, 9);

            window.__blattaActiveCall = false;

            // Aggregate call state onto the top frame, keyed by frame, so a call
            // running inside a same-origin iframe is still seen by the pool's
            // main-frame check (evaluateJavaScript runs in the main frame only).
            // Cross-origin frames can't reach window.top (property access
            // throws), so they fall back to their own flag — an inherent limit.
            function updateCallState() {
                var active = activePeers.size > 0;
                try {
                    var top = window.top || window;
                    if (!top.__blattaCallFrames) top.__blattaCallFrames = {};
                    if (active) {
                        top.__blattaCallFrames[frameId] = true;
                    } else {
                        delete top.__blattaCallFrames[frameId];
                    }
                    top.__blattaActiveCall = Object.keys(top.__blattaCallFrames).length > 0;
                } catch (e) {
                    window.__blattaActiveCall = active;
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
    /// Blatta. **This covers the page-side call only.** A notification raised
    /// from inside the service worker — the push path — runs in a worker context
    /// no page script can enter, and is still not intercepted.
    ///
    /// The original constructor is still called so the page gets a real
    /// `Notification` back to hold `onclick`/`close()` on. That cannot double up
    /// today: WebKit only delivers web notifications to an app that adopts the
    /// `WKUIDelegate` notification methods, and Blatta adopts none of them, so
    /// the original object is inert for display.
    private func makeNotificationInterceptionScript() -> String {
        return """
        (function() {
            function forward(title, options) {
                try {
                    window.webkit.messageHandlers.blattaNotification.postMessage(
                        JSON.stringify({
                            version: 1,
                            type: 'web-notification',
                            title: title == null ? '' : String(title),
                            body: (options && options.body) || '',
                            tag: (options && options.tag) || ''
                        })
                    );
                } catch (e) {
                    // A page that has torn down the bridge must not take the
                    // site's own notification call down with it.
                }
            }

            var OrigNotification = window.Notification;
            if (OrigNotification) {
                var BlattaNotification = function(title, options) {
                    forward(title, options);
                    return new OrigNotification(title, options);
                };

                // Same prototype object, so `instanceof Notification` holds for
                // instances the original constructor returns.
                BlattaNotification.prototype = OrigNotification.prototype;

                // Carry every static across, descriptors and all, before the two
                // overrides below replace the ones Blatta answers itself.
                Object.getOwnPropertyNames(OrigNotification).forEach(function(key) {
                    if (key === 'prototype' || key === 'name' || key === 'length') return;
                    try {
                        var descriptor = Object.getOwnPropertyDescriptor(OrigNotification, key);
                        if (descriptor) Object.defineProperty(BlattaNotification, key, descriptor);
                    } catch (e) {}
                });

                Object.defineProperty(BlattaNotification, 'permission', {
                    get: function() { return 'granted'; },
                    configurable: true
                });
                BlattaNotification.requestPermission = function(cb) {
                    if (cb) cb('granted');
                    return Promise.resolve('granted');
                };

                window.Notification = BlattaNotification;
            }

            if (window.ServiceWorkerRegistration &&
                window.ServiceWorkerRegistration.prototype &&
                window.ServiceWorkerRegistration.prototype.showNotification) {
                var origShow = window.ServiceWorkerRegistration.prototype.showNotification;
                window.ServiceWorkerRegistration.prototype.showNotification = function(title, options) {
                    forward(title, options);
                    return origShow.apply(this, arguments);
                };
            }
        })();
        """
    }
}
