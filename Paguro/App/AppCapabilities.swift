import Foundation
import PaguroCore

#if APP_STORE && DIRECT_DISTRIBUTION
#error("Select only one distribution: APP_STORE or DIRECT_DISTRIBUTION")
#endif

/// Central switches for platform capabilities that depend on an Apple approval
/// or build configuration, so feature-gated UI is driven from one place rather
/// than scattered booleans.
enum AppCapabilities {
    #if APP_STORE
    static let distribution = AppDistribution.appStore
    #elseif DIRECT_DISTRIBUTION
    static let distribution = AppDistribution.directDownload
    #else
    static let distribution = AppDistribution.development
    #endif

    static let selfUpdatesSupported = distribution.supportsSelfUpdates
    static let googleIconFallbackSupported = distribution.supportsGoogleIconFallback

    /// Passkey (WebAuthn) sign-in works inside `WKWebView` only when the app
    /// holds the Apple-managed `com.apple.developer.web-browser.public-key-credential`
    /// entitlement, which must be requested from and granted by Apple. Until
    /// then, passkey prompts fail inside Paguro, so the UI steers users to
    /// password + two-factor sign-in.
    ///
    /// Flip to `true` once the entitlement is granted, added to the
    /// entitlements file, and provisioned. See DISTRIBUTION.md.
    static let passkeysSupported = false

    /// Liquid Glass arrived in macOS 26. Below that the shell draws the same
    /// material surfaces for every glass style, so the style choice would show
    /// options that cannot change the native glass appearance.
    ///
    /// Earlier systems use the solid shell fallback without glass controls.
    static var liquidGlassSupported: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// Text of the floating notice card that shows the first time a service
    /// opens. The Add Service sheet does not repeat it.
    static let passkeyUnavailableBanner =
        "Passkeys aren't available for sign-in here. Apple doesn't let apps like Paguro use them, so sign in with your password or another method."
}
