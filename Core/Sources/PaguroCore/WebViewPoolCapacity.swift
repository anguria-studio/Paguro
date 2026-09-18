import Foundation

/// The size limit of the live web-view pool.
///
/// The limit is separate from idle hibernation. It applies even when the user
/// turns idle hibernation off, because each live service keeps its own web
/// content process and its own memory.
public enum WebViewPoolCapacity {
    /// The largest number of services that keep a live web view at the same time.
    ///
    /// Above this number the pool releases the least recently used services that
    /// no exemption protects. The value is provisional. ATL-301 must measure the
    /// memory cost of a live service before this number becomes final.
    public static let maxLoaded: Int = 15
}
