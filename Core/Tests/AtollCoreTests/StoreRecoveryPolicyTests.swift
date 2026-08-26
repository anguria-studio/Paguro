import Foundation
import XCTest
@testable import AtollCore

final class StoreRecoveryPolicyTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/store-recovery-policy")

    func testContentComparisonAndSeedMatching() {
        let fullest = content(spaces: 4, services: 13)
        let fewerServices = content(spaces: 9, services: 12)
        let fewerSpaces = content(spaces: 2, services: 13)

        XCTAssertTrue(fullest.holdsMore(than: fewerServices))
        XCTAssertTrue(fullest.holdsMore(than: fewerSpaces))
        XCTAssertFalse(fullest.holdsMore(than: fullest))

        let seed = StoreContent(
            spaces: 2,
            services: 3,
            links: 3,
            spaceNames: ["Work", "Personal"],
            serviceLabels: ["Mail", "Chat", "Mail"]
        )
        XCTAssertTrue(seed.matchesUntouchedSeed(
            spaceNames: ["Personal", "Work"],
            serviceLabels: ["Mail", "Mail", "Chat"]
        ))
        XCTAssertFalse(seed.matchesUntouchedSeed(
            spaceNames: ["Personal", "Clients"],
            serviceLabels: ["Mail", "Mail", "Chat"]
        ))
    }

    func testBestCandidateRanksContentThenRecency() {
        let fullOld = candidate("a", spaces: 4, services: 13, takenAt: 1_000)
        let thinNew = candidate("b", spaces: 2, services: 7, takenAt: 9_000)
        let fullNew = candidate("c", kind: .prerestore, spaces: 4, services: 13, takenAt: 5_000)
        let live = candidate("live", kind: .live, spaces: 9, services: 99, takenAt: 9_999)
        let damaged = candidate("d", spaces: 8, services: 40, takenAt: 9_500, damaged: true)
        let unreadable = candidate("e", spaces: 0, services: 0, takenAt: 9_600, unreadable: true)

        XCTAssertEqual(
            StoreRecoveryPolicy.best(among: [fullOld, thinNew, fullNew, live, damaged, unreadable]),
            fullNew
        )
        XCTAssertEqual(StoreRecoveryPolicy.best(among: [thinNew, fullOld]), fullOld)
        XCTAssertNil(StoreRecoveryPolicy.best(among: [live, damaged, unreadable]))

        let fewerLinks = StoreCandidate(
            url: directory.appendingPathComponent("fewer-links"),
            kind: .snapshot(version: nil),
            takenAt: Date(timeIntervalSince1970: 10_000),
            content: StoreContent(
                spaces: 4,
                services: 13,
                links: 12,
                spaceNames: [],
                serviceLabels: []
            ),
            isDamaged: false
        )
        XCTAssertEqual(StoreRecoveryPolicy.best(among: [fullOld, fewerLinks]), fullOld)
    }

    func testRankingBreaksCompleteTiesByPath() {
        let first = candidate("a.bak", spaces: 2, services: 7, takenAt: 1_000)
        let second = candidate("b.bak", spaces: 2, services: 7, takenAt: 1_000)

        XCTAssertNotEqual(
            StoreRecoveryPolicy.isRankedAbove(first, second),
            StoreRecoveryPolicy.isRankedAbove(second, first)
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.best(among: [first, second]),
            StoreRecoveryPolicy.best(among: [second, first])
        )
    }

    func testPreselectionProtectsUserDataAndSkipsCorruptBackups() {
        let backup = candidate("snapshot.bak", spaces: 4, services: 13, takenAt: 1_000)
        let corrupt = candidate(
            "corrupt.bak",
            kind: .corrupt,
            spaces: 9,
            services: 40,
            takenAt: 2_000
        )
        let empty = content(spaces: 0, services: 0)
        let seed = content(spaces: 2, services: 7)
        let userData = content(spaces: 3, services: 10)

        XCTAssertEqual(StoreRecoveryPolicy.preselection(
            among: [backup],
            liveContent: empty,
            liveMatchesUntouchedSeed: false
        ), backup)
        XCTAssertEqual(StoreRecoveryPolicy.preselection(
            among: [backup],
            liveContent: seed,
            liveMatchesUntouchedSeed: true
        ), backup)
        XCTAssertEqual(StoreRecoveryPolicy.preselection(
            among: [backup],
            liveContent: nil,
            liveMatchesUntouchedSeed: false
        ), backup)
        XCTAssertNil(StoreRecoveryPolicy.preselection(
            among: [backup],
            liveContent: userData,
            liveMatchesUntouchedSeed: false
        ))
        XCTAssertEqual(StoreRecoveryPolicy.preselection(
            among: [corrupt, backup],
            liveContent: empty,
            liveMatchesUntouchedSeed: false
        ), backup)
        XCTAssertNil(StoreRecoveryPolicy.preselection(
            among: [corrupt],
            liveContent: empty,
            liveMatchesUntouchedSeed: false
        ))

        let emptyBackup = candidate("empty.bak", spaces: 0, services: 0, takenAt: 3_000)
        XCTAssertNil(StoreRecoveryPolicy.preselection(
            among: [emptyBackup],
            liveContent: empty,
            liveMatchesUntouchedSeed: false
        ))
    }

    func testOfferRuleCoversLossSeedDeclineAndUnknownContent() {
        let backup = candidate("snapshot.bak", spaces: 4, services: 13, takenAt: 1_000)
        let thin = candidate("thin.bak", spaces: 1, services: 2, takenAt: 2_000)
        let partial = content(spaces: 1, services: 4)
        let seed = content(spaces: 2, services: 7)
        let record = content(spaces: 4, services: 13)

        XCTAssertEqual(StoreRecoveryPolicy.offer(
            liveContent: partial,
            liveMatchesUntouchedSeed: false,
            best: backup,
            record: record,
            declinedKeys: []
        ), .belowRecord)
        XCTAssertEqual(StoreRecoveryPolicy.offer(
            liveContent: seed,
            liveMatchesUntouchedSeed: true,
            best: backup,
            record: nil,
            declinedKeys: []
        ), .nothingToLose)
        XCTAssertNil(StoreRecoveryPolicy.offer(
            liveContent: partial,
            liveMatchesUntouchedSeed: false,
            best: backup,
            record: partial,
            declinedKeys: []
        ))
        XCTAssertNil(StoreRecoveryPolicy.offer(
            liveContent: partial,
            liveMatchesUntouchedSeed: false,
            best: thin,
            record: record,
            declinedKeys: []
        ))
        XCTAssertNil(StoreRecoveryPolicy.offer(
            liveContent: partial,
            liveMatchesUntouchedSeed: false,
            best: nil,
            record: record,
            declinedKeys: []
        ))

        let decline = StoreRecoveryPolicy.declineKey(live: partial, candidate: backup)
        XCTAssertNil(StoreRecoveryPolicy.offer(
            liveContent: partial,
            liveMatchesUntouchedSeed: false,
            best: backup,
            record: record,
            declinedKeys: [decline]
        ))
        XCTAssertNotNil(StoreRecoveryPolicy.offer(
            liveContent: seed,
            liveMatchesUntouchedSeed: true,
            best: backup,
            record: record,
            declinedKeys: [decline]
        ))
        XCTAssertEqual(StoreRecoveryPolicy.offer(
            liveContent: nil,
            liveMatchesUntouchedSeed: false,
            best: thin,
            record: record,
            declinedKeys: []
        ), .belowRecord)
        XCTAssertEqual(StoreRecoveryPolicy.offer(
            liveContent: nil,
            liveMatchesUntouchedSeed: false,
            best: thin,
            record: nil,
            declinedKeys: []
        ), .nothingToLose)
    }

    func testContentRecordRoundTrip() throws {
        let original = content(spaces: 4, services: 13)
        let encoded = StoreRecoveryPolicy.encodeRecord(original)
        let decoded = try XCTUnwrap(StoreRecoveryPolicy.decodeRecord(encoded))

        XCTAssertEqual(decoded.spaces, 4)
        XCTAssertEqual(decoded.services, 13)
        XCTAssertEqual(decoded.links, 13)
        XCTAssertNil(StoreRecoveryPolicy.decodeRecord("garbage"))
        XCTAssertNil(StoreRecoveryPolicy.decodeRecord("4-13"))
        XCTAssertNil(StoreRecoveryPolicy.decodeRecord(""))
    }

    func testRestoreNameValidation() {
        let store = "default.store"
        for name in [
            "default.store.snapshot-1700000000-1.5.11+20.bak",
            "default.store.prerestore-1700000000.bak",
            "default.store.corrupt-1700000000.bak",
            "default.store.prepick-1700000000.bak",
        ] {
            XCTAssertEqual(
                StoreRecoveryPolicy.validatedRestoreName(name, storeName: store),
                name
            )
        }
        for name in [
            "../../etc/passwd",
            "/tmp/default.store.snapshot-1.bak",
            "default.store.snapshot-1/../x.bak",
            "default.store",
            "other.store.snapshot-1.bak",
            "default.store.snapshot-1.txt",
            "",
        ] {
            XCTAssertNil(StoreRecoveryPolicy.validatedRestoreName(name, storeName: store), name)
        }
    }

    func testRecoveryPlanNeverOverwritesLiveData() {
        XCTAssertEqual(
            StoreRecoveryPolicy.recoveryPlan(
                kind: .emptiedWithHistory,
                before: 4,
                fileExisted: true
            ),
            StoreRecoveryPlan(attemptRestore: true, ifNoRestore: .preserveInMemory)
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.recoveryPlan(
                kind: .emptiedWithHistory,
                before: nil,
                fileExisted: false
            ),
            StoreRecoveryPlan(attemptRestore: true, ifNoRestore: .freshStart)
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.recoveryPlan(
                kind: .openFailed,
                before: 5,
                fileExisted: true
            ),
            StoreRecoveryPlan(attemptRestore: false, ifNoRestore: .preserveInMemory)
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.recoveryPlan(
                kind: .openFailed,
                before: 0,
                fileExisted: true
            ),
            StoreRecoveryPlan(attemptRestore: true, ifNoRestore: .preserveInMemory)
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.recoveryPlan(
                kind: .openFailed,
                before: nil,
                fileExisted: true
            ),
            StoreRecoveryPlan(attemptRestore: true, ifNoRestore: .preserveInMemory)
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.recoveryPlan(
                kind: .openFailed,
                before: nil,
                fileExisted: false
            ),
            StoreRecoveryPlan(attemptRestore: true, ifNoRestore: .freshStart)
        )
    }

    private func content(spaces: Int, services: Int) -> StoreContent {
        StoreContent(
            spaces: spaces,
            services: services,
            links: services,
            spaceNames: [],
            serviceLabels: []
        )
    }

    private func candidate(
        _ name: String,
        kind: StoreCandidate.Kind = .snapshot(version: nil),
        spaces: Int,
        services: Int,
        takenAt: TimeInterval,
        damaged: Bool = false,
        unreadable: Bool = false
    ) -> StoreCandidate {
        StoreCandidate(
            url: directory.appendingPathComponent(name),
            kind: kind,
            takenAt: Date(timeIntervalSince1970: takenAt),
            content: unreadable ? nil : content(spaces: spaces, services: services),
            isDamaged: damaged
        )
    }
}
