import Foundation

/// The color-scheme signal that Blatta gives to one web service.
///
/// Automatic follows the Blatta window. Light and dark are explicit overrides.
/// This uses the web app's own `prefers-color-scheme` support. It does not
/// recolor the page.
enum ServiceAppearanceMode: String, CaseIterable {
    case automatic, light, dark

    var displayName: String {
        switch self {
        case .automatic: return "Follow Blatta"
        case .light: return "Always Light"
        case .dark: return "Always Dark"
        }
    }

    func usesDarkAppearance(shellIsDark: Bool) -> Bool {
        switch self {
        case .automatic: return shellIsDark
        case .light: return false
        case .dark: return true
        }
    }

    /// Maps values written by the old Dark Reader control onto native web
    /// appearance. An old Off or Auto value now follows Blatta. An old On value
    /// remains dark, but uses the service's own dark-theme support.
    static func resolving(storedRaw: String?, legacyForceDark: Bool?) -> Self {
        switch storedRaw {
        case Self.automatic.rawValue, "auto", "off": return .automatic
        case Self.light.rawValue: return .light
        case Self.dark.rawValue, "on": return .dark
        default: return legacyForceDark == true ? .dark : .automatic
        }
    }
}
