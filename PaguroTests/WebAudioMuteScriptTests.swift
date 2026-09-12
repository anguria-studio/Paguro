import JavaScriptCore
import XCTest
@testable import Paguro

final class WebAudioMuteScriptTests: XCTestCase {
    @MainActor
    func testGainCoversNewContextsAndPreservesConnectionAndDisconnectionContracts() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
            var window = this;
            window.frames = []; window.parent = window;
            window.addEventListener = function() {};
            var createdGains = [];
            class AudioNode {
                constructor(context) { this.context = context; this.connections = []; }
                connect(destination, ...ports) {
                    this.connections.push([destination, ...ports]); return destination;
                }
                disconnect(...args) { this.disconnected = args; }
            }
            class AudioContext {
                constructor() { this.destination = new AudioNode(this); }
                createGain() {
                    const gain = new AudioNode(this); gain.gain = {value: 1};
                    createdGains.push(gain); return gain;
                }
            }
            window.AudioContext = AudioContext; window.AudioNode = AudioNode;
            """)
        context.evaluateScript(WebAudioMuteScript.source(muted: true))
        XCTAssertNil(context.exception)
        context.evaluateScript("""
            var first = new AudioContext();
            var source = new AudioNode(first);
            var result = source.connect(first.destination, 0, 0);
            """)
        XCTAssertTrue(context.evaluateScript("result === first.destination")!.toBool())
        XCTAssertTrue(context.evaluateScript("source.connections[0][0] === createdGains[0]")!.toBool())
        XCTAssertTrue(context.evaluateScript("createdGains[0].connections[0][0] === first.destination")!.toBool())
        XCTAssertEqual(context.evaluateScript("createdGains[0].gain.value")!.toInt32(), 0)
        context.evaluateScript("source.disconnect(first.destination, 0, 0)")
        XCTAssertTrue(context.evaluateScript("source.disconnected[0] === createdGains[0]")!.toBool())
        context.evaluateScript("source.disconnect(0)")
        XCTAssertEqual(context.evaluateScript("source.disconnected[0]")!.toInt32(), 0)
        context.evaluateScript("source.disconnect()")
        XCTAssertEqual(context.evaluateScript("source.disconnected.length")!.toInt32(), 0)
        context.evaluateScript("""
            var second = new AudioContext();
            new AudioNode(second).connect(second.destination);
            """)
        XCTAssertEqual(context.evaluateScript("createdGains[1].gain.value")!.toInt32(), 0)
        context.evaluateScript("window.__paguroSetMediaMuted(false)")
        XCTAssertTrue(context.evaluateScript("createdGains.every(gain => gain.gain.value === 1)")!.toBool())
        context.evaluateScript("window.__paguroSetMediaMuted(true)")
        XCTAssertTrue(context.evaluateScript("createdGains.every(gain => gain.gain.value === 0)")!.toBool())
        context.evaluateScript("window.__paguroSetMediaMuted('false')")
        XCTAssertTrue(context.evaluateScript("createdGains.every(gain => gain.gain.value === 0)")!.toBool())
        // Offline rendering and connections to ordinary nodes stay unchanged.
        context.evaluateScript("""
            var offline = {destination: {}};
            var offlineSource = new AudioNode(offline);
            offlineSource.connect(offline.destination);
            var intermediate = new AudioNode(first);
            source.connect(intermediate);
            """)
        XCTAssertTrue(context.evaluateScript("offlineSource.connections[0][0] === offline.destination")!.toBool())
        XCTAssertTrue(context.evaluateScript("source.connections[1][0] === intermediate")!.toBool())
        XCTAssertEqual(context.evaluateScript("createdGains.length")!.toInt32(), 2)
        XCTAssertNil(context.exception)
    }
}
