import AppKit
import BlattaCore
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

    /// The list that the content header shows. The handler reports plain values
    /// to it and keeps every WebKit object here.
    weak var tracker: DownloadTracker?

    /// The service that owns this handler's transfers. `WebViewCoordinator`
    /// sets it, so the header can show only the active service's downloads.
    var serviceID: UUID?

    /// Blatta's identifier for each live transfer. `WKDownload` has none.
    private var trackedIDs: [ObjectIdentifier: UUID] = [:]

    /// Publishes byte counts while a transfer runs.
    ///
    /// `WKDownload.progress` is a `Progress`, and its KVO notifications arrive
    /// on an unspecified thread. Reading it on a main-actor tick keeps every
    /// value on one actor and costs one small read for each live transfer.
    private var progressTask: Task<Void, Never>?

    /// The gap between two progress reads. It is short enough for a smooth
    /// ring and long enough to stay off the hot path.
    private static let progressInterval: Duration = .milliseconds(150)

    /// Takes ownership of a transfer handed off by a navigation delegate.
    func track(_ download: WKDownload) {
        download.delegate = self
        activeDownloads.insert(download)
        Self.activeHandlers.insert(self)

        let id = UUID()
        trackedIDs[ObjectIdentifier(download)] = id
        tracker?.begin(
            id: id,
            serviceID: serviceID,
            filename: Self.provisionalFilename(for: download),
            cancel: { [weak download] in download?.cancel(nil) }
        )
        startProgressUpdates()
    }

    /// The best name available before WebKit reports the suggested filename.
    private static func provisionalFilename(for download: WKDownload) -> String {
        let component = download.originalRequest?.url?.lastPathComponent ?? ""
        return component.isEmpty ? "Download" : component
    }

    private func startProgressUpdates() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while true {
                guard !Task.isCancelled, let self, !self.activeDownloads.isEmpty else { break }
                self.publishProgress()
                try? await Task.sleep(for: Self.progressInterval)
            }
            self?.progressTask = nil
        }
    }

    private func publishProgress() {
        guard let tracker else { return }
        for download in activeDownloads {
            guard let id = trackedIDs[ObjectIdentifier(download)] else { continue }
            let progress = download.progress
            tracker.updateProgress(
                id: id,
                received: progress.completedUnitCount,
                expected: progress.totalUnitCount
            )
        }
    }

    /// Removes a transfer from the tracker's live set.
    private func trackedID(for download: WKDownload, removing: Bool) -> UUID? {
        let key = ObjectIdentifier(download)
        return removing ? trackedIDs.removeValue(forKey: key) : trackedIDs[key]
    }

    /// Cancels the transfers owned by this handler. A terminated WebContent
    /// process cannot be trusted to send their final callbacks.
    func cancelActiveDownloads() {
        guard !activeDownloads.isEmpty else { return }
        for download in activeDownloads {
            download.cancel(nil)
            if let id = trackedID(for: download, removing: true) {
                tracker?.markCancelled(id: id)
            }
        }
        activeDownloads.removeAll()
        destinations.removeAll()
        progressTask?.cancel()
        progressTask = nil
        Self.activeHandlers.remove(self)
    }

    /// Cancels every in-flight transfer. `Command-Q` must stop all Blatta work.
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
        if let id = trackedID(for: download, removing: false) {
            tracker?.setDestination(id: id, destination: destination)
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        let destination = destinations.removeValue(forKey: ObjectIdentifier(download))
        let id = trackedID(for: download, removing: true)
        untrack(download)
        if let id {
            tracker?.finish(id: id, destination: destination)
        }
        guard let destination else { return }

        AppLogger.webView.info("Download finished: \(destination.lastPathComponent)")
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("com.apple.DownloadFileFinished"),
            object: destination.path
        )
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        let id = trackedID(for: download, removing: true)
        untrack(download)
        if let id {
            if Self.isCancellation(error) {
                tracker?.markCancelled(id: id)
            } else {
                tracker?.fail(id: id)
            }
        }
        AppLogger.webView.error("Download failed: \(error.localizedDescription)")
    }

    /// Whether a failure is the result of `WKDownload.cancel(_:)`.
    ///
    /// A user stop and a broken connection reach the same delegate method. The
    /// indicator shows a failure mark only for the broken connection.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
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
        if activeDownloads.isEmpty {
            progressTask?.cancel()
            progressTask = nil
            Self.activeHandlers.remove(self)
        }
    }
}
