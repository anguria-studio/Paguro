#if !APP_STORE
import Foundation
import PaguroCore

@available(macOS 15.4, *)
extension BrowserExtensionManager {
    var availableUpdates: [UUID: FirefoxAddonRelease] {
        Dictionary(uniqueKeysWithValues: records.compactMap { record in
            guard let entry = updateChecks.entries[record.id.uuidString], entry.installedSHA256 == record.sha256,
                  let release = entry.available, ExtensionUpdatePolicy.isUpdate(release, for: record) else { return nil }
            return (record.id, release)
        })
    }

    var automaticUpdateChecksEnabled: Bool { updateChecks.isEnabled }

    func restoreUpdateChecks() {
        guard FileManager.default.fileExists(atPath: updateStateURL.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: updateStateURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 512 * 1_024 + 1) ?? Data()
            guard data.count <= 512 * 1_024 else { throw Failure.invalidLibrary }
            let state = try JSONDecoder().decode(ExtensionUpdateChecks.self, from: data)
            guard state.isValid else { throw Failure.invalidLibrary }
            updateChecks = state
            updateChecks.prune(for: records)
        } catch {
            updateChecks = ExtensionUpdateChecks()
            updateChecks.isEnabled = false
            errorMessage = "Could not read extension update settings. Background checks are paused."
        }
    }

    private func saveUpdateChecks(_ state: ExtensionUpdateChecks) throws {
        guard state.isValid else { throw Failure.invalidLibrary }
        let data = try JSONEncoder().encode(state)
        guard data.count <= 512 * 1_024 else { throw Failure.invalidLibrary }
        try data.write(to: updateStateURL, options: .atomic)
        updateChecks = state
    }

    func setAutomaticUpdateChecks(_ enabled: Bool) {
        guard permitsUpdateChecks, !isBusy else { return }
        errorMessage = nil
        var next = updateChecks
        next.isEnabled = enabled
        do {
            try saveUpdateChecks(next)
            if enabled { resumeUpdateChecks() } else { suspendUpdateChecks() }
        } catch { errorMessage = "Could not save extension update settings." }
    }

    func refreshUpdateChecks() {
        var next = updateChecks
        next.prune(for: records)
        updateCheckErrors = updateCheckErrors.filter { id, _ in records.contains { $0.id == id } }
        do { try saveUpdateChecks(next) }
        catch { errorMessage = "Could not save extension update status." }
        if updatesStarted { checkForUpdates() }
    }

    func resumeUpdateChecks() {
        guard updatesStarted, permitsUpdateChecks, updateChecks.isEnabled, updateMonitor == nil else { return }
        updateMonitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.checkForUpdates()
                do { try await Task.sleep(for: .seconds(ExtensionUpdatePolicy.pollInterval)) }
                catch { return }
            }
        }
    }

    func suspendUpdateChecks() {
        updateMonitor?.cancel()
        updateMonitor = nil
        updateRun = UUID()
        updateWork?.cancel()
        updateWork = nil
        isCheckingUpdates = false
    }

    func checkForUpdates(force: Bool = false, ids: Set<UUID>? = nil) {
        guard permitsUpdateChecks, !isBusy, updateWork == nil, force || updateChecks.isEnabled else { return }
        let selected = records.filter {
            (ids?.contains($0.id) ?? true) && (force || ExtensionUpdatePolicy.shouldCheck($0, entry: updateChecks.entries[$0.id.uuidString], now: now()))
        }
        guard !selected.isEmpty else { return }
        let run = UUID()
        updateRun = run
        isCheckingUpdates = true
        updateWork = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.updateRun == run { self.updateWork = nil; self.isCheckingUpdates = false }
            }
            for record in selected {
                guard !Task.isCancelled, self.permitsUpdateChecks, self.updateRun == run else { return }
                let source = try? FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/\(record.slug)/")
                guard let source else { continue }
                var candidate = self.availableUpdates[record.id]
                var succeeded = false
                do {
                    let release = try await self.fetchRelease(source)
                    guard release.isValid, release.slug == record.slug,
                          FirefoxExtensionVersion.compare(release.version, record.version) != nil else { throw FirefoxAddonClient.Failure.unavailable }
                    candidate = ExtensionUpdatePolicy.isUpdate(release, for: record) ? release : nil
                    succeeded = true
                } catch is CancellationError { return }
                catch { }
                guard !Task.isCancelled, self.permitsUpdateChecks, self.updateRun == run else { return }
                guard self.records.contains(where: { $0 == record }) else { continue }
                var state = self.updateChecks
                state.entries[record.id.uuidString] = ExtensionUpdateCheck(installedSHA256: record.sha256,
                    checkedAt: self.now(), available: candidate)
                do {
                    try self.saveUpdateChecks(state)
                    self.updateCheckErrors[record.id] = succeeded ? nil : "Could not check for updates. Try again later."
                } catch {
                    // Keep the cooldown in memory when the disk is unavailable.
                    self.updateChecks = state
                    self.updateCheckErrors[record.id] = "Could not save the update check. Try again later."
                }
            }
        }
    }

    func reviewUpdate(_ id: UUID) {
        guard permitsUpdateChecks, let record = records.first(where: { $0.id == id }), availableUpdates[id] != nil else { return }
        // Cached metadata never selects executable bytes. Fetch the current package for a new review.
        review(link: "https://addons.mozilla.org/firefox/addon/\(record.slug)/")
    }
}
#endif
