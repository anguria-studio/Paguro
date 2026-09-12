import Foundation
import Observation
import PaguroCore

/// Owns cancellable icon discovery while the add-service form is open.
@MainActor
@Observable
final class ServiceIconDraft {
    private(set) var customIconData: Data?
    private(set) var fetchedIconData: Data?
    private(set) var isFetching = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let fetch: @Sendable (String) async -> Data?
    @ObservationIgnored private let pause: @Sendable () async throws -> Void

    init(
        fetch: @escaping @Sendable (String) async -> Data? = {
            await FaviconFetcher.shared.fetchFavicon(for: $0)
        },
        pause: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(600))
        }
    ) {
        self.fetch = fetch
        self.pause = pause
    }

    func updateURL(_ value: String) {
        let url = normalizedServiceURL(value)
        guard url != sourceURL else {
            if fetchedIconData == nil && !isFetching { discover() }
            return
        }
        cancel()
        sourceURL = url
        fetchedIconData = nil
        errorMessage = nil
        discover()
    }

    func chooseImage(_ data: Data) {
        do {
            let normalized = try ServiceIconImageProcessor.normalizedPNG(from: data)
            cancel()
            customIconData = normalized
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useWebsiteIcon() {
        cancel()
        customIconData = nil
        errorMessage = nil
        if fetchedIconData == nil { discover() }
    }

    func showError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isFetching = false
    }

    /// The save action also checks the address, before SwiftUI's onChange runs.
    func fetchedIcon(for value: String) -> Data? {
        guard normalizedServiceURL(value) == sourceURL else { return nil }
        return fetchedIconData
    }

    private func normalizedServiceURL(_ value: String) -> URL? {
        guard case .valid(_, let address) = CustomServiceInputValidator.validate(
            label: "Service", url: value
        ) else { return nil }
        return ServiceIconSource.normalizedURL(from: address, fallbackURL: "")
    }

    private func discover() {
        guard let sourceURL, customIconData == nil else { return }
        let token = generation
        isFetching = true
        task = Task { [weak self, fetch, pause] in
            do { try await pause() } catch { return }
            guard !Task.isCancelled else { return }
            let data = await fetch(sourceURL.absoluteString)
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.isFetching = false
            self.task = nil
            // A missing or invalid website image keeps the initial-letter tile.
            self.fetchedIconData = data.flatMap { try? ServiceIconImageProcessor.normalizedPNG(from: $0) }
        }
    }
}
