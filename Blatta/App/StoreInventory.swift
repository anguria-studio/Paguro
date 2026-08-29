import Foundation
import SQLite3
import BlattaCore

/// The spaces and services `WorkspaceStore` writes on a genuine fresh
/// install. Shared with `StoreContent.looksLikeUntouchedSeed` so the seeder and
/// the fingerprint can never drift apart; `testSeededStoreIsFingerprintedAsSeed`
/// fails if they do.
enum DefaultSeed {
    static let spaces: [(name: String, emoji: String)] = [
        (name: "Personal", emoji: "🏠"),
        (name: "Work", emoji: "💼"),
    ]

    static let personalServices: [(label: String, url: String, catalogID: String)] = [
        (label: "Gmail", url: "https://mail.google.com/mail/u/0/#inbox", catalogID: "gmail"),
        (label: "Discord", url: "https://discord.com/channels/@me", catalogID: "discord"),
        (label: "ChatGPT", url: "https://chatgpt.com", catalogID: "chatgpt"),
        (label: "Claude", url: "https://claude.ai", catalogID: "claude"),
    ]

    static let workServices: [(label: String, url: String, catalogID: String)] = [
        (label: "Gmail", url: "https://mail.google.com/mail/u/0/#inbox", catalogID: "gmail"),
        (label: "Slack", url: "https://app.slack.com/client", catalogID: "slack"),
        (label: "Outlook", url: "https://outlook.cloud.microsoft/mail/", catalogID: "outlook"),
    ]

    /// Every seeded service label, including the duplicate Gmail that appears in
    /// both spaces. Compared as a multiset, so the duplicate matters.
    static var allServiceLabels: [String] {
        (personalServices + workServices).map(\.label)
    }
}

extension StoreContent {
    /// True only when the store is exactly what `WorkspaceStore`
    /// writes: the two seeded spaces, the seven seeded services, nothing added,
    /// nothing renamed. A store like this holds nothing of the user's, which is
    /// what makes it safe to preselect a backup over.
    var looksLikeUntouchedSeed: Bool {
        matchesUntouchedSeed(
            spaceNames: DefaultSeed.spaces.map(\.name),
            serviceLabels: DefaultSeed.allServiceLabels
        )
    }
}

/// Reads store files without opening a `ModelContainer`, so candidates can be
/// inspected and ranked before anything migrates or locks them. Read-only
/// throughout: nothing here writes to a store.
enum StoreInventory {
    private static let spaceTable = "ZSPACE"
    private static let serviceTable = "ZSERVICEINSTANCE"
    private static let linkTable = "ZSPACESERVICELINK"

    /// What the store at `url` holds, or nil when that cannot be established:
    /// no file, a file that is not a database, or a schema without the tables
    /// this app owns. Nil is "unknown" and callers must not read it as empty.
    ///
    /// Opened via `openReadOnly`, whose doc explains why the plain read-only
    /// open never uses `immutable=1`, and the narrow case where the fallback
    /// does.
    static func readContent(at url: URL) -> StoreContent? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let db = openReadOnly(url) else { return nil }
        defer { sqlite3_close(db) }

        // Require this app's tables before counting; an unrecognized schema is
        // unknown, not empty.
        let known = scalarInt(db, """
            SELECT COUNT(*) FROM sqlite_master WHERE type='table'
             AND name IN ('\(spaceTable)','\(serviceTable)','\(linkTable)');
            """) ?? 0
        guard known == 3 else { return nil }

        guard let spaces = scalarInt(db, "SELECT COUNT(*) FROM \(spaceTable);"),
              let services = scalarInt(db, "SELECT COUNT(*) FROM \(serviceTable);"),
              let links = scalarInt(db, "SELECT COUNT(*) FROM \(linkTable);") else {
            return nil
        }
        return StoreContent(
            spaces: spaces,
            services: services,
            links: links,
            spaceNames: textColumn(db, "SELECT ZNAME FROM \(spaceTable);"),
            serviceLabels: textColumn(db, "SELECT ZLABEL FROM \(serviceTable);")
        )
    }

    /// Whether the store at `url` passes an integrity check. `(1)` stops at the
    /// first error, which bounds the cost when several candidates are checked at
    /// launch.
    static func passesIntegrityCheck(at url: URL) -> Bool {
        guard let db = openReadOnly(url) else { return false }
        defer { sqlite3_close(db) }
        return scalarText(db, "PRAGMA integrity_check(1);") == "ok"
    }

    // MARK: - SQLite helpers

    /// Opens `url` read-only with a busy timeout, or nil if that fails. Not
    /// `private`: `StoreRepair.spaceCount` shares this opener rather than
    /// keeping its own copy, so the fallback below only has to be written once.
    ///
    /// Tries a plain read-only open first — never URI-style, never
    /// `immutable=1` on this path: a `.bak` can sit beside a `-wal` holding
    /// committed-but-uncheckpointed rows, and an immutable open ignores the
    /// WAL, which would silently under-count it.
    ///
    /// A WAL-mode SQLite file's header records that fact permanently, even
    /// after its `-wal`/`-shm` siblings are gone (a clean close checkpoints
    /// and can remove them, and `StoreRepair.snapshot` only copies the
    /// suffixes that exist at backup time). On at least this SQLite build,
    /// such a file's plain `SQLITE_OPEN_READONLY` connection opens without
    /// error (`sqlite3_open_v2` is lazy) but then fails with `SQLITE_CANTOPEN`
    /// on the *first real read* — a read-only connection can't create the
    /// `-shm` it needs. `probeOpens` forces that first read immediately, so
    /// this can be detected here rather than surfacing later as a mysterious
    /// nil count. If the probe fails AND no `-wal` sibling exists, retry once
    /// with `immutable=1`. That retry can never hide committed rows in this
    /// specific case, because there is no `-wal` for it to ignore — the
    /// "no -wal" check is what keeps this fallback from ever applying to the
    /// case the plain-open rule above exists to protect.
    static func openReadOnly(_ url: URL) -> OpaquePointer? {
        if let db = rawOpen(url.path, flags: SQLITE_OPEN_READONLY) {
            if probeOpens(db) { return db }
            sqlite3_close(db)
        }

        guard !FileManager.default.fileExists(atPath: url.path + "-wal") else { return nil }

        guard let fallback = rawOpen("file:\(url.path)?immutable=1", flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI) else {
            return nil
        }
        guard probeOpens(fallback) else {
            sqlite3_close(fallback)
            return nil
        }
        return fallback
    }

    /// Opens `path` with `flags` and a busy timeout, or nil if `sqlite3_open_v2`
    /// itself reports failure. Closes any handle SQLite allocates even on
    /// failure; callers own closing the handle they get back on success.
    private static func rawOpen(_ path: String, flags: Int32) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let opened = db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(opened, 3000)
        return opened
    }

    /// Forces the lazy `sqlite3_open_v2` to actually touch the file, by
    /// reading its first page. `sqlite3_open_v2` alone can report success on a
    /// file it will fail to open once a query actually runs, which is exactly
    /// the WAL-header/no-`-shm` case this function exists to catch early.
    private static func probeOpens(_ db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func scalarInt(_ db: OpaquePointer, _ sql: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func scalarText(_ db: OpaquePointer, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    /// Every non-null value of a single text column. Nulls are skipped rather
    /// than turned into empty strings, so a null name cannot look like a rename.
    private static func textColumn(_ db: OpaquePointer, _ sql: String) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var values: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                values.append(String(cString: cString))
            }
        }
        return values
    }
}

/// The picker row's two display strings. Hoisted out of `StoreRecoveryView` so
/// the label matrix — five kinds, singular/plural counts, the unknown-date and
/// nil-content fallbacks, the damaged marker, and the live row's own rule — is
/// unit-testable without a running `AppState` or any SwiftUI machinery.
extension StoreCandidate {
    /// A one-line label naming which store this candidate is. Exhaustive over
    /// `Kind`, deliberately with no `default:` case: a new backup family added
    /// there must get its own label rather than silently falling through to
    /// the wrong text.
    var displayTitle: String {
        switch kind {
        case .live: return "Your data now"
        case .snapshot(let version): return version.map { "Backup from before \($0)" } ?? "Backup from before an update"
        case .prerestore: return "Backup from an earlier restore"
        case .corrupt: return "Backup from before a repair"
        case .prepick: return "Your data before you restored a backup"
        }
    }

    /// The row's secondary line: what the store holds, plus when it was taken
    /// for a backup.
    ///
    /// The live row omits the date entirely. `takenAt` for `.live` is the main
    /// `.store` file's modification time (see `StoreInventory.candidates`),
    /// and under WAL journaling that timestamp lags the real last write — the
    /// live row could show an older date than a backup while actually holding
    /// the newer data, which argues for restoring the wrong copy. The `Current`
    /// capsule already marks which row this is, so nothing is lost by leaving
    /// the date off.
    var displayDetail: String {
        let counts: String
        if let content {
            let spaces = content.spaces == 1 ? "1 workspace" : "\(content.spaces) workspaces"
            let services = content.services == 1 ? "1 service" : "\(content.services) services"
            // `content == nil` is the only unreadable case (see below), so a
            // damaged-but-readable file is the only place this marker applies;
            // it can never double up with the nil-content "can't be read" text.
            let damaged = isDamaged ? " — damaged" : ""
            counts = "\(spaces), \(services)\(damaged)"
        } else {
            counts = "can't be read"
        }
        guard kind != .live else { return counts }
        return "\(dateDescription) — \(counts)"
    }

    private var dateDescription: String {
        guard let takenAt else { return "date unknown" }
        return Self.dateFormatter.string(from: takenAt)
    }

    /// One formatter, not one per row per redraw.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension StoreInventory {
    /// Every candidate for `storeURL`: the live store (whose content the caller
    /// supplies, since it is already open) plus each backup sibling, ordered
    /// most-complete-first (see `StoreRecoveryPolicy.isRankedAbove`). Unreadable
    /// and damaged files are included so the user can see they exist, but sort
    /// to the bottom of the backups. The live row always leads.
    static func candidates(for storeURL: URL, liveContent: StoreContent?) -> [StoreCandidate] {
        let live = StoreCandidate(
            url: storeURL,
            kind: .live,
            takenAt: (try? FileManager.default.attributesOfItem(atPath: storeURL.path)[.modificationDate]) as? Date,
            content: liveContent,
            isDamaged: false
        )

        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return [live]
        }

        var backups: [StoreCandidate] = []
        for name in names where name.hasSuffix(".bak") {
            guard let infix = StoreRecoveryPolicy.backupInfixes.first(where: { name.hasPrefix(base + $0) }),
                  let family = StoreBackupFamily(rawValue: infix) else { continue }
            let url = dir.appending(path: name)
            // StoreRepair owns the filename timestamp parser because it creates
            // the same backup names.
            let parsed = StoreRepair.stampAndVersion(name, prefix: base + infix)
            let kind: StoreCandidate.Kind
            switch family {
            case .snapshot: kind = .snapshot(version: parsed.version)
            case .prerestore: kind = .prerestore
            case .corrupt: kind = .corrupt
            case .prepick: kind = .prepick
            }
            let content = readContent(at: url)
            backups.append(StoreCandidate(
                url: url,
                kind: kind,
                takenAt: parsed.stamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                content: content,
                // Only pay for an integrity check on a file we could read at all.
                isDamaged: content == nil || !passesIntegrityCheck(at: url)
            ))
        }
        // Most-complete-first, the same rule the picker uses to choose a
        // winner. Filename order can place damaged repairs before intact
        // snapshots, so it is not a safe recovery order.
        backups.sort(by: StoreRecoveryPolicy.isRankedAbove)
        return [live] + backups
    }
}
