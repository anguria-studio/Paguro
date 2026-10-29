#if !APP_STORE
import WebKit

/// Fill standard constants only where WebKit already exposes their native API.
@MainActor
enum BrowserExtensionAPICompatibility {
    static let identifier = "scripting.ExecutionWorld"

    static func configure(_ configuration: WKWebViewConfiguration) {
        let content = configuration.userContentController
        guard !content.userScripts.contains(where: { $0.source == executionWorldConstants }) else { return }
        content.addUserScript(WKUserScript(source: executionWorldConstants,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }

    // Document hooks do not run in extension workers. Leave those APIs native.
    static let executionWorldConstants = """
        (() => {
            if (location.protocol !== 'webkit-extension:') return;
            for (const api of [globalThis.browser, globalThis.chrome]) {
                const scripting = api?.scripting;
                if (!scripting || typeof scripting.executeScript !== 'function' ||
                    'ExecutionWorld' in scripting || !Object.isExtensible(scripting)) continue;
                Object.defineProperty(scripting, 'ExecutionWorld', {
                    value: {MAIN:'MAIN', ISOLATED:'ISOLATED'},
                    enumerable:true, configurable:true, writable:true
                });
            }
        })();
        """
}
#endif
