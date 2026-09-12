import WebKit

/// WebKit suspension does not silence an AudioContext created after suspension.
/// An output gain for each context covers that path without identifying a sound.
@MainActor
enum WebAudioMuteScript {
    private static let marker = "// Paguro Web Audio mute\n"

    static func apply(muted: Bool, to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        // Copy the bridged collection before changing WebKit's user scripts.
        let scripts = controller.userScripts.filter { !$0.source.hasPrefix(marker) }
        controller.removeAllUserScripts()
        for script in scripts { controller.addUserScript(script) }
        controller.addUserScript(WKUserScript(
            source: source(muted: muted), injectionTime: .atDocumentStart, forMainFrameOnly: false
        ))
        webView.evaluateJavaScript("window.__paguroSetMediaMuted?.(\(muted))", completionHandler: nil)
    }

    static func source(muted: Bool) -> String {
        marker + """
        (() => {
            let muted = \(muted);
            const Context = window.AudioContext || window.webkitAudioContext;
            if (!window.AudioNode || !Context) return;
            const gains = new Set();
            const contextGains = new WeakMap();
            const connect = AudioNode.prototype.connect;
            const disconnect = AudioNode.prototype.disconnect;
            const createGain = Context.prototype.createGain;

            function updateGains() {
                for (const reference of gains) {
                    const gain = reference.deref();
                    if (gain) gain.gain.value = muted ? 0 : 1;
                    else gains.delete(reference);
                }
            }
            function output(node, destination) {
                const context = node.context;
                // Offline rendering does not produce speaker output.
                if (!(context instanceof Context) || destination !== context.destination) {
                    return destination;
                }
                let gain = contextGains.get(context);
                if (!gain) {
                    gain = createGain.call(context);
                    gain.gain.value = muted ? 0 : 1;
                    connect.call(gain, context.destination);
                    contextGains.set(context, gain);
                    gains.add(new WeakRef(gain));
                    updateGains();
                }
                return gain;
            }
            AudioNode.prototype.connect = function(destination, ...ports) {
                const target = output(this, destination);
                const result = connect.call(this, target, ...ports);
                return target === destination ? result : destination;
            };
            AudioNode.prototype.disconnect = function(...args) {
                if (args.length) args[0] = output(this, args[0]);
                return disconnect.apply(this, args);
            };

            function send(frame) {
                frame.postMessage({type: 'paguro-media-mute', muted}, '*');
            }
            window.__paguroSetMediaMuted = function(value) {
                if (typeof value !== 'boolean') return;
                muted = value;
                updateGains();
                for (let i = 0; i < window.frames.length; i++) send(window.frames[i]);
            };
            window.addEventListener('message', event => {
                if (event.data?.type === 'paguro-media-mute' && window !== window.parent &&
                    event.source === window.parent) {
                    window.__paguroSetMediaMuted(event.data.muted);
                } else if (event.data?.type === 'paguro-media-mute-request') {
                    for (let i = 0; i < window.frames.length; i++) {
                        if (event.source === window.frames[i]) send(event.source);
                    }
                }
            });
            if (window !== window.parent) {
                window.parent.postMessage({type: 'paguro-media-mute-request'}, '*');
            }
        })();
        """
    }
}
