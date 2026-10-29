import Foundation
import WebKit

@MainActor
protocol BrowserExtensionHosting: AnyObject {
    func configure(_ configuration: WKWebViewConfiguration, for service: ServiceInstance)
    func didCreate(_ webView: WKWebView, for serviceID: UUID)
    func didActivate(_ serviceID: UUID?)
    func didNavigate(_ serviceID: UUID)
    func customUserAgent(defaultValue: String, for serviceID: UUID) -> String?
    func setLocked(_ locked: Bool)
    func release(_ serviceID: UUID)
    func shutdown()
}

extension BrowserExtensionHosting {
    func customUserAgent(defaultValue: String, for serviceID: UUID) -> String? { defaultValue }
}

/// The availability boundary keeps the macOS 15.0 application free of newer stored types.
@MainActor
final class BrowserExtensionFeature {
    let host: (any BrowserExtensionHosting)?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if !APP_STORE
        if #available(macOS 15.4, *), arguments.contains("--paguro-browser-extensions"),
           AppCapabilities.distribution.supportsExperimentalBrowserExtensions,
           !Self.isFirstRunPreview(arguments) {
            #if DEBUG
            let parent = "Paguro-debug"
            #else
            let parent = "Paguro"
            #endif
            let directory = URL.applicationSupportDirectory
                .appending(path: parent).appending(path: "BrowserExtensionsPrototype-v1")
            host = BrowserExtensionManager(directory: directory)
            return
        }
        #endif
        host = nil
    }

    /// The first-run preview exists only in Debug builds. Release builds must
    /// not contain its launch argument, so the check compiles away there.
    private static func isFirstRunPreview(_ arguments: [String]) -> Bool {
        #if DEBUG
        FirstRunPreviewConfiguration.isEnabled(arguments: arguments)
        #else
        false
        #endif
    }

    #if !APP_STORE
    @available(macOS 15.4, *)
    var manager: BrowserExtensionManager? { host as? BrowserExtensionManager }
    #endif
}
