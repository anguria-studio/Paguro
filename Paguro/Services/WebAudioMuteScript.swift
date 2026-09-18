import WebKit

/// WebKit suspension does not silence an AudioContext created after suspension.
/// An output gain for each context covers that path without identifying a sound.
///
/// The same interposition point also measures the sound. Every connection to a
/// context destination gets a side branch to an `AnalyserNode`, and a small
/// page-side sampler records the last time that branch carried a signal. A page
/// that produces sound with no media element at all — WhatsApp Web decodes a
/// voice message itself and plays it through Web Audio — is visible only there.
@MainActor
enum WebAudioMuteScript {
    private static let marker = "// Paguro Web Audio mute\n"

    /// The name of the page-side reader of the Web Audio measurement. It is long
    /// and prefixed, so a page is unlikely to hold the same name, and it is
    /// defined as a non-enumerable property, so a page that lists the properties
    /// of `window` does not see it.
    ///
    /// It answers `{running, since}`: how many tapped contexts run now, and how
    /// many milliseconds ago the output last carried a signal, or -1 for never.
    /// The audibility probe reads it; nothing writes through it.
    nonisolated static let stateReaderName = "__paguroWebAudioState"

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
            const createAnalyser = Context.prototype.createAnalyser;

            // Level above which the output counts as sound. 0.001 is about
            // -60 dBFS: far below anything a listener calls audible, and far
            // above the zero that an idle context sends to its destination.
            const signalThreshold = 0.001;
            const squaredThreshold = signalThreshold * signalThreshold;
            // One sample window. 1024 frames are about 21 ms at 48 kHz, which is
            // enough for a level and short enough to copy on every tick.
            const windowSize = 1024;
            // A tick reads one small buffer for each context, so 250 ms costs
            // almost nothing. A background page throttles its timers to about
            // one tick per second; the probe window covers that.
            const sampleInterval = 250;
            const taps = new Set();
            const contextTaps = new WeakMap();
            let lastSignalAt = -1;
            let sampler = 0;

            function sample() {
                try {
                    let live = 0;
                    for (const entry of taps) {
                        const analyser = entry.analyser;
                        if (analyser.context.state === 'closed') {
                            // The context is over, so nothing holds it any more.
                            taps.delete(entry);
                            contextTaps.delete(analyser.context);
                            continue;
                        }
                        live++;
                        // A suspended context sends nothing to the speakers.
                        if (analyser.context.state !== 'running') continue;
                        const samples = entry.samples;
                        analyser.getFloatTimeDomainData(samples);
                        let sum = 0;
                        for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
                        // The mean square against the squared threshold is the
                        // RMS test without the square root.
                        if (sum > squaredThreshold * samples.length) {
                            lastSignalAt = performance.now();
                        }
                    }
                    // No context left to measure, so the page keeps no timer.
                    if (!live) {
                        clearInterval(sampler);
                        sampler = 0;
                    }
                } catch (e) {}
            }
            // The analyser for one context, created once. It has no output of
            // its own, so it observes the signal without changing what the user
            // hears, and it cannot reach the destination. A node that cannot
            // reach the destination is collected as soon as no reference holds
            // it, so the tap holds it until the context closes. The output gains
            // need no such reference: each one sits in the path to the speakers.
            function tap(context) {
                let entry = contextTaps.get(context);
                if (entry) return entry.analyser;
                const analyser = createAnalyser.call(context);
                analyser.fftSize = windowSize;
                entry = {
                    analyser: analyser,
                    // One buffer for each analyser, reused by every tick.
                    samples: new Float32Array(analyser.fftSize)
                };
                contextTaps.set(context, entry);
                taps.add(entry);
                if (!sampler) sampler = setInterval(sample, sampleInterval);
                return analyser;
            }
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
                if (target !== destination) {
                    // Measure what the page sends, before the mute gain, so the
                    // answer stays "the page produces sound" while muted. The
                    // same output port feeds the branch, and a repeated
                    // connection between the same two ports changes nothing.
                    try { connect.call(this, tap(this.context), ports[0] || 0); } catch (e) {}
                }
                const result = connect.call(this, target, ...ports);
                return target === destination ? result : destination;
            };
            AudioNode.prototype.disconnect = function(...args) {
                if (args.length) {
                    const target = output(this, args[0]);
                    if (target !== args[0]) {
                        // A node that no longer reaches the speakers must leave
                        // the measurement as well.
                        const entry = contextTaps.get(this.context);
                        if (entry) {
                            try {
                                disconnect.call(this, entry.analyser, ...args.slice(1));
                            } catch (e) {}
                        }
                    }
                    args[0] = target;
                }
                return disconnect.apply(this, args);
            };
            try {
                if (!Object.getOwnPropertyDescriptor(window, '\(stateReaderName)')) {
                    Object.defineProperty(window, '\(stateReaderName)', {
                        // The reader answers counts only, and it answers even
                        // when something in the page is unusual: a report of no
                        // context and no signal counts as silence.
                        value: function() {
                            let running = 0;
                            let since = -1;
                            try {
                                for (const entry of taps) {
                                    if (entry.analyser.context.state === 'running') running++;
                                }
                                if (lastSignalAt >= 0) {
                                    since = Math.max(0, performance.now() - lastSignalAt);
                                }
                            } catch (e) {}
                            return {running: running, since: since};
                        },
                        configurable: false,
                        enumerable: false,
                        writable: false
                    });
                }
            } catch (e) {}

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
