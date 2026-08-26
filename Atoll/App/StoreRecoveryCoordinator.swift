import Foundation
import SwiftData
import AtollCore

/// Coordinates user-visible store recovery after the model container opens.
@MainActor
@Observable
final class StoreRecoveryCoordinator {
    /// A launch warning or recovery notice shown above the main content.
    struct Banner: Equatable {
        let message: String
        let folderURL: URL?
        let isDismissible: Bool
    }

    static let maxDeclinedRestores = 20

    private let context: ModelContext
    private let storeURL: URL
    private let storeFileName: String
    private let defaults: UserDefaults
    @ObservationIgnored private let armRelaunch: @MainActor () -> Bool
    @ObservationIgnored private let quit: @MainActor () -> Void
    private let isInMemoryFallback: Bool
    private let wasDamagedAtLaunch: Bool
    private let wasRestoredAtLaunch: Bool

    private(set) var banner: Banner?
    private(set) var offer: StoreRecoveryOffer?
    private(set) var candidates: [StoreCandidate] = []
    private(set) var preselectedCandidate: StoreCandidate?
    private(set) var isRestartArmed = false
    var isShowingPicker = false

    /// Irreversible cleanup is unsafe when the live container may not represent
    /// the store that existed before this launch.
    var isSafeToReclaim: Bool {
        !isInMemoryFallback && !wasDamagedAtLaunch && !wasRestoredAtLaunch
    }

    init(
        context: ModelContext,
        storeURL: URL,
        outcome: StoreLoadOutcome,
        wasDamagedAtLaunch: Bool,
        defaults: UserDefaults = .standard,
        armRelaunch: @escaping @MainActor () -> Bool = { AppRelauncher.armRelaunch() },
        quit: @escaping @MainActor () -> Void = { AppRelauncher.quit() }
    ) {
        self.context = context
        self.storeURL = storeURL
        self.storeFileName = storeURL.lastPathComponent
        self.defaults = defaults
        self.armRelaunch = armRelaunch
        self.quit = quit
        self.wasDamagedAtLaunch = wasDamagedAtLaunch

        switch outcome {
        case .openedClean:
            isInMemoryFallback = false
            wasRestoredAtLaunch = false
            banner = nil
        case .restoredFromSnapshot(_, let takenAt):
            isInMemoryFallback = false
            wasRestoredAtLaunch = true
            let when: String
            if let takenAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                when = " taken \(formatter.string(from: takenAt))"
            } else {
                when = ""
            }
            banner = Banner(
                message: "Atoll recovered your data from an automatic backup\(when).",
                folderURL: nil,
                isDismissible: true
            )
        case .inMemoryFallback:
            isInMemoryFallback = true
            wasRestoredAtLaunch = false
            let folderURL = storeURL.deletingLastPathComponent()
            banner = Banner(
                message: "Your saved data couldn't be loaded, so Atoll is running with temporary storage — changes won't be saved. Atoll keeps automatic backups from before each update; your data folder (with those backups) is at: \(folderURL.path)",
                folderURL: folderURL,
                isDismissible: false
            )
        }
    }

    func dismissBanner() {
        guard banner?.isDismissible == true else { return }
        banner = nil
    }

    /// Evaluates the launch-time restore offer and prepares the picker.
    func evaluateOffer() {
        let live = currentLiveContent()
        let currentCandidates = StoreInventory.candidates(for: storeURL, liveContent: live)
        let best = StoreRecoveryPolicy.best(among: currentCandidates)
        let declined = Set(defaults.stringArray(forKey: DefaultsKey.declinedRestores) ?? [])
        let liveMatchesSeed = live?.looksLikeUntouchedSeed ?? false

        candidates = currentCandidates
        offer = StoreRecoveryPolicy.offer(
            liveContent: live,
            liveMatchesUntouchedSeed: liveMatchesSeed,
            best: best,
            record: StoreRecoveryPolicy.decodeRecord(
                defaults.string(forKey: DefaultsKey.lastKnownContent)
            ),
            declinedKeys: declined
        )
        preselectedCandidate = StoreRecoveryPolicy.preselection(
            among: currentCandidates,
            liveContent: live,
            liveMatchesUntouchedSeed: liveMatchesSeed
        )
        if let offer {
            AppLogger.dataStore.notice(
                "Offering a store restore (\(String(describing: offer))); candidates=\(currentCandidates.count)"
            )
        }
    }

    /// Refreshes picker rows without changing the launch-time offer.
    func refreshCandidates() {
        let live = currentLiveContent()
        let currentCandidates = StoreInventory.candidates(for: storeURL, liveContent: live)
        candidates = currentCandidates
        preselectedCandidate = StoreRecoveryPolicy.preselection(
            among: currentCandidates,
            liveContent: live,
            liveMatchesUntouchedSeed: live?.looksLikeUntouchedSeed ?? false
        )
    }

    /// Records the exact evaluated live-store and backup pairing. Reusing the
    /// candidate list keeps fallback launches tied to the on-disk store.
    func declineOffer() {
        if let best = StoreRecoveryPolicy.best(among: candidates) {
            let liveContent = candidates.first(where: { $0.kind == .live })?.content
            let key = StoreRecoveryPolicy.declineKey(live: liveContent, candidate: best)
            var declined = defaults.stringArray(forKey: DefaultsKey.declinedRestores) ?? []
            if !declined.contains(key) {
                declined.append(key)
                defaults.set(
                    Array(declined.suffix(Self.maxDeclinedRestores)),
                    forKey: DefaultsKey.declinedRestores
                )
            }
        }
        offer = nil
    }

    /// Records the current store shape when it is safe to replace the history.
    /// An unreadable, empty, or temporary store is not evidence of deletion.
    /// An active offer or scheduled restore also needs the older record intact.
    func recordContent() {
        let content = liveContent()
        guard Self.shouldRecordContent(
            content,
            offerOutstanding: offer != nil,
            isInMemoryFallback: isInMemoryFallback,
            restoreScheduled: defaults.string(forKey: DefaultsKey.pendingRestore) != nil
        ), let content else { return }
        defaults.set(StoreRecoveryPolicy.encodeRecord(content), forKey: DefaultsKey.lastKnownContent)
    }

    /// Validates the selected backup and arms a restart after the picker closes.
    /// If relaunch arming fails, the durable restore key remains for the next
    /// manual launch and the picker stays open with an error.
    @discardableResult
    func chooseRestore(_ candidate: StoreCandidate) -> Bool {
        guard Self.scheduleRestore(
            candidate,
            storeName: storeFileName,
            defaults: defaults
        ) else { return false }
        guard armRelaunch() else {
            AppLogger.dataStore.error(
                "Restore was scheduled but the relaunch could not be spawned; it will still apply on the next launch"
            )
            return false
        }
        offer = nil
        isRestartArmed = true
        return true
    }

    /// Quits once after a successful selection and picker dismissal.
    func quitForScheduledRestore() {
        guard isRestartArmed else { return }
        isRestartArmed = false
        quit()
    }

    /// Returns whether the current store shape can replace the recovery record.
    static func shouldRecordContent(
        _ content: StoreContent?,
        offerOutstanding: Bool,
        isInMemoryFallback: Bool,
        restoreScheduled: Bool
    ) -> Bool {
        guard !isInMemoryFallback else { return false }
        guard !offerOutstanding else { return false }
        guard !restoreScheduled else { return false }
        guard let content, !content.isEmpty else { return false }
        return true
    }

    /// Writes the validated filename that the next launch will restore.
    @discardableResult
    nonisolated static func scheduleRestore(
        _ candidate: StoreCandidate,
        storeName: String,
        defaults: UserDefaults
    ) -> Bool {
        guard candidate.isRestorable else { return false }
        guard let name = StoreRecoveryPolicy.validatedRestoreName(
            candidate.url.lastPathComponent,
            storeName: storeName
        ) else {
            AppLogger.dataStore.error(
                "Refusing to schedule a restore from an unexpected filename"
            )
            return false
        }
        defaults.set(name, forKey: DefaultsKey.pendingRestore)
        AppLogger.dataStore.info("Scheduled a restore from \(name)")
        return true
    }

    private func liveContent() -> StoreContent? {
        do {
            return StoreContent(
                spaces: try context.fetchCount(FetchDescriptor<Space>()),
                services: try context.fetchCount(FetchDescriptor<ServiceInstance>()),
                links: try context.fetchCount(FetchDescriptor<SpaceServiceLink>()),
                spaceNames: try context.fetch(FetchDescriptor<Space>()).map(\.name),
                serviceLabels: try context.fetch(FetchDescriptor<ServiceInstance>()).map(\.label)
            )
        } catch {
            AppLogger.dataStore.error(
                "Could not read live store content: \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Reads the file during fallback because the temporary container does not
    /// represent the user's on-disk store.
    private func currentLiveContent() -> StoreContent? {
        isInMemoryFallback ? StoreInventory.readContent(at: storeURL) : liveContent()
    }
}
