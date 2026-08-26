import Foundation

/// The contents used to compare live stores and backups.
public struct StoreContent: Hashable, Sendable {
    public let spaces: Int
    public let services: Int
    public let links: Int
    public let spaceNames: [String]
    public let serviceLabels: [String]

    public init(
        spaces: Int,
        services: Int,
        links: Int,
        spaceNames: [String],
        serviceLabels: [String]
    ) {
        self.spaces = spaces
        self.services = services
        self.links = links
        self.spaceNames = spaceNames
        self.serviceLabels = serviceLabels
    }

    public var isEmpty: Bool { spaces == 0 && services == 0 }

    /// Returns whether this store holds more services, or the same number of
    /// services in more workspaces.
    public func holdsMore(than other: StoreContent) -> Bool {
        if services != other.services { return services > other.services }
        return spaces > other.spaces
    }

    /// Returns whether this content exactly matches a known initial seed.
    public func matchesUntouchedSeed(
        spaceNames seedSpaceNames: [String],
        serviceLabels seedServiceLabels: [String]
    ) -> Bool {
        spaces == seedSpaceNames.count
            && services == seedServiceLabels.count
            && spaceNames.sorted() == seedSpaceNames.sorted()
            && serviceLabels.sorted() == seedServiceLabels.sorted()
    }
}

/// One live store or backup that Atoll can show in the recovery picker.
public struct StoreCandidate: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case live
        case snapshot(version: String?)
        case prerestore
        case corrupt
        case prepick
    }

    public let url: URL
    public let kind: Kind
    public let takenAt: Date?
    public let content: StoreContent?
    public let isDamaged: Bool

    public init(
        url: URL,
        kind: Kind,
        takenAt: Date?,
        content: StoreContent?,
        isDamaged: Bool
    ) {
        self.url = url
        self.kind = kind
        self.takenAt = takenAt
        self.content = content
        self.isDamaged = isDamaged
    }

    public var id: String { url.path }

    /// Returns whether this candidate is a readable, intact backup.
    public var isRestorable: Bool {
        kind != .live && content != nil && !isDamaged
    }
}

/// A filename family used for automatic and user-selected backups.
public enum StoreBackupFamily: String, CaseIterable, Sendable {
    case snapshot = ".snapshot-"
    case prerestore = ".prerestore-"
    case corrupt = ".corrupt-"
    case prepick = ".prepick-"
}

/// Why Atoll offers to restore a backup.
public enum StoreRecoveryOffer: Equatable, Sendable {
    case belowRecord
    case nothingToLose
}

/// Why a persistent store could not be used.
public enum StoreUnusableKind: Equatable, Sendable {
    case emptiedWithHistory
    case openFailed
}

/// What to do when no automatic restore is available.
public enum StoreRecoveryFallback: Equatable, Sendable {
    case preserveInMemory
    case freshStart
}

/// The deterministic part of automatic store recovery.
public struct StoreRecoveryPlan: Equatable, Sendable {
    public let attemptRestore: Bool
    public let ifNoRestore: StoreRecoveryFallback

    public init(attemptRestore: Bool, ifNoRestore: StoreRecoveryFallback) {
        self.attemptRestore = attemptRestore
        self.ifNoRestore = ifNoRestore
    }
}

/// Pure rules for ranking, offering, and validating store recovery.
public enum StoreRecoveryPolicy {
    public static let backupInfixes = StoreBackupFamily.allCases.map(\.rawValue)

    /// Returns whether `lhs` ranks above `rhs` in the recovery picker.
    /// Restorable candidates lead. Content size, date, and path then form a
    /// total order, so filesystem enumeration cannot change the selected item.
    public static func isRankedAbove(_ lhs: StoreCandidate, _ rhs: StoreCandidate) -> Bool {
        switch (lhs.isRestorable, rhs.isRestorable) {
        case (true, false): return true
        case (false, true): return false
        case (false, false): return lhs.url.path < rhs.url.path
        case (true, true): break
        }

        guard let lhsContent = lhs.content, let rhsContent = rhs.content else {
            return lhs.url.path < rhs.url.path
        }
        if lhsContent.services != rhsContent.services {
            return lhsContent.services > rhsContent.services
        }
        if lhsContent.spaces != rhsContent.spaces {
            return lhsContent.spaces > rhsContent.spaces
        }
        if lhsContent.links != rhsContent.links {
            return lhsContent.links > rhsContent.links
        }
        let lhsTakenAt = lhs.takenAt ?? .distantPast
        let rhsTakenAt = rhs.takenAt ?? .distantPast
        if lhsTakenAt != rhsTakenAt { return lhsTakenAt > rhsTakenAt }
        return lhs.url.path < rhs.url.path
    }

    /// Returns the highest-ranked readable, intact backup.
    public static func best(among candidates: [StoreCandidate]) -> StoreCandidate? {
        candidates
            .filter(\.isRestorable)
            .sorted(by: isRankedAbove)
            .first
    }

    /// Returns the safe default selection for the recovery picker.
    /// A default is safe only when the live store is empty, unreadable, or the
    /// untouched seed. A corrupt-family backup is never selected by default.
    public static func preselection(
        among candidates: [StoreCandidate],
        liveContent: StoreContent?,
        liveMatchesUntouchedSeed: Bool
    ) -> StoreCandidate? {
        let liveHoldsUserData = liveContent.map {
            !$0.isEmpty && !liveMatchesUntouchedSeed
        } ?? false
        guard !liveHoldsUserData else { return nil }
        guard let winner = best(among: candidates.filter { $0.kind != .corrupt }) else {
            return nil
        }
        if let liveContent,
           let backupContent = winner.content,
           !backupContent.holdsMore(than: liveContent) {
            return nil
        }
        return winner
    }

    /// Returns whether Atoll should offer a restore, and why.
    /// The backup must cover the live-store gap and the same pairing must not
    /// have been declined. A saved record detects later loss. The untouched
    /// seed also permits an offer when no older record exists.
    public static func offer(
        liveContent: StoreContent?,
        liveMatchesUntouchedSeed: Bool,
        best: StoreCandidate?,
        record: StoreContent?,
        declinedKeys: Set<String>
    ) -> StoreRecoveryOffer? {
        guard let best, let backup = best.content, best.isRestorable else { return nil }
        if let liveContent, !backup.holdsMore(than: liveContent) { return nil }
        if declinedKeys.contains(declineKey(live: liveContent, candidate: best)) {
            return nil
        }

        if let record, let liveContent, record.holdsMore(than: liveContent) {
            return .belowRecord
        }
        if let record, liveContent == nil, !record.isEmpty { return .belowRecord }

        let liveHoldsUserData = liveContent.map {
            !$0.isEmpty && !liveMatchesUntouchedSeed
        } ?? false
        return liveHoldsUserData ? nil : .nothingToLose
    }

    /// Returns a stable key for one backup and live-store pairing.
    public static func declineKey(
        live: StoreContent?,
        candidate: StoreCandidate
    ) -> String {
        let liveSignature = live.map {
            "\($0.spaces)-\($0.services)-\($0.links)"
        } ?? "unknown"
        return "\(candidate.url.lastPathComponent)|\(liveSignature)"
    }

    /// Returns the compact form stored in user defaults.
    public static func encodeRecord(_ content: StoreContent) -> String {
        "\(content.spaces)-\(content.services)-\(content.links)"
    }

    /// Parses a content record. Invalid input means that no record exists.
    public static func decodeRecord(_ raw: String?) -> StoreContent? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let spaces = Int(parts[0]),
              let services = Int(parts[1]),
              let links = Int(parts[2]) else {
            return nil
        }
        return StoreContent(
            spaces: spaces,
            services: services,
            links: links,
            spaceNames: [],
            serviceLabels: []
        )
    }

    /// Validates an untrusted backup filename before file access. The value can
    /// come from user defaults, so it must be a plain filename in a known
    /// backup family for the active store.
    public static func validatedRestoreName(
        _ name: String,
        storeName: String
    ) -> String? {
        guard !name.isEmpty,
              !name.contains("/"),
              !name.contains(".."),
              name.hasSuffix(".bak"),
              backupInfixes.contains(where: { name.hasPrefix(storeName + $0) }) else {
            return nil
        }
        return name
    }

    /// Decides whether to restore an unusable store and how to fall back.
    ///
    /// A failed open must never overwrite a store that still has rows. The
    /// failure can be temporary while the newest data remains intact. An empty
    /// or unreadable store can use a backup because the file operation first
    /// preserves the current store. A fresh start is safe only when no file
    /// existed and no restore is available.
    public static func recoveryPlan(
        kind: StoreUnusableKind,
        before: Int?,
        fileExisted: Bool
    ) -> StoreRecoveryPlan {
        switch kind {
        case .emptiedWithHistory:
            return StoreRecoveryPlan(
                attemptRestore: true,
                ifNoRestore: fileExisted ? .preserveInMemory : .freshStart
            )
        case .openFailed:
            if (before ?? 0) > 0 {
                return StoreRecoveryPlan(
                    attemptRestore: false,
                    ifNoRestore: .preserveInMemory
                )
            }
            return StoreRecoveryPlan(
                attemptRestore: true,
                ifNoRestore: fileExisted ? .preserveInMemory : .freshStart
            )
        }
    }
}
