import AppKit
import AtollCore
import Foundation
import WebKit

/// Owns WebKit downloads after a navigation hands them off.
///
/// Active handlers retain themselves through the process registry. This lets a
/// transfer finish after its source web view and coordinator are hibernated.
@MainActor
final class WebDownloadHandler: NSObject, WKDownloadDelegate {
    /// Maps each transfer to its chosen destination. `WKDownload` does not
    /// provide that URL again when it finishes.
    private var destinations: [ObjectIdentifier: URL] = [:]

    /// Keeps transfers reachable when WebKit does not deliver a final callback.
    private var activeDownloads: Set<WKDownload> = []

    /// Keeps active handlers alive and lets application shutdown cancel every
    /// transfer, including transfers whose source web view no longer exists.
    private static var activeHandlers: Set<WebDownloadHandler> = []

    /// Takes ownership of a transfer handed off by a navigation delegate.
    func track(_ download: WKDownload) {
        download.delegate = self
        activeDownloads.insert(download)
        Self.activeHandlers.insert(self)
    }

    /// Cancels the transfers owned by this handler. A terminated WebContent
    /// process cannot be trusted to send their final callbacks.
    func cancelActiveDownloads() {
        guard !activeDownloads.isEmpty else { return }
        for download in activeDownloads { download.cancel(nil) }
        activeDownloads.removeAll()
        destinations.removeAll()
        Self.activeHandlers.remove(self)
    }

    /// Cancels every in-flight transfer. `Command-Q` must stop all Atoll work.
    static func cancelAllDownloads() {
        for handler in activeHandlers {
            handler.cancelActiveDownloads()
        }
        activeHandlers.removeAll()
    }

    /// Saves to the Downloads folder with a browser-style unique name.
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let fileManager = FileManager.default
        let downloads: URL
        do {
            downloads = try fileManager.url(
                for: .downloadsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            AppLogger.webView.error("Couldn't locate the Downloads folder: \(error.localizedDescription)")
            return nil
        }

        let filename = WebRoutingPolicy.sanitizedDownloadFilename(suggestedFilename)
        let destination = Self.nonCollidingURL(
            in: downloads,
            filename: filename,
            fileExists: { fileManager.fileExists(atPath: $0.path) }
        )
        destinations[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        let destination = destinations.removeValue(forKey: ObjectIdentifier(download))
        untrack(download)
        guard let destination else { return }

        AppLogger.webView.info("Download finished: \(destination.lastPathComponent)")
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("com.apple.DownloadFileFinished"),
            object: destination.path
        )
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        untrack(download)
        AppLogger.webView.error("Download failed: \(error.localizedDescription)")
    }

    /// Whether a response explicitly asks to be saved instead of displayed.
    nonisolated static func isAttachment(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition") else {
            return false
        }
        return disposition.lowercased().contains("attachment")
    }

    /// Returns a free destination by adding a numeric suffix before the file
    /// extension when needed.
    nonisolated static func nonCollidingURL(
        in directory: URL,
        filename: String,
        fileExists: (URL) -> Bool
    ) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard fileExists(candidate) else { return candidate }

        let filenameParts = filename as NSString
        let fileExtension = filenameParts.pathExtension
        let base = filenameParts.deletingPathExtension
        var index = 1
        while true {
            let name = fileExtension.isEmpty
                ? "\(base) (\(index))"
                : "\(base) (\(index)).\(fileExtension)"
            let url = directory.appendingPathComponent(name)
            if !fileExists(url) { return url }
            index += 1
        }
    }

    private func untrack(_ download: WKDownload) {
        activeDownloads.remove(download)
        if activeDownloads.isEmpty { Self.activeHandlers.remove(self) }
    }
}
