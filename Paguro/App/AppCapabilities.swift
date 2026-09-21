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

    /// The continuous system glass control is available from macOS 27.
    /// macOS 26 keeps manual presets; earlier systems use the solid palette.
    static var shellGlassSupport: ShellGlassSupport {
        if #available(macOS 27, *) { return .systemAppearance }
        if #available(macOS 26, *) { return .presets }
        return .unavailable
    }

    static var liquidGlassSupported: Bool {
        !shellGlassSupport.availableStyles.isEmpty
    }

    /// Text of the floating notice card that shows the first time a service
    /// opens. The Add Service sheet does not repeat it.
    static let passkeyUnavailableBanner =
        "Passkeys aren't available for sign-in here. Apple doesn't let apps like Paguro use them, so sign in with your password or another method."
}
