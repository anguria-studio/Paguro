import Foundation
import Testing
@testable import PaguroCore

struct QuitStorageFlushPolicyTests {
    private struct Store: Equatable {
        var name: String
        var id: UUID?
        var isPersistent: Bool
    }

    @Test
    func limitsMatchTheMeasuredValues() {
        #expect(QuitStorageFlushPolicy.timeout == .milliseconds(500))
        #expect(QuitStorageFlushPolicy.minimumWait == .milliseconds(50))
    }

    @Test
    func minimumWaitFillsTheRemainingTime() {
        #expect(QuitStorageFlushPolicy.remainingMinimumWait(elapsed: .zero) == .milliseconds(50))
        #expect(QuitStorageFlushPolicy.remainingMinimumWait(elapsed: .milliseconds(15)) == .milliseconds(35))
        #expect(QuitStorageFlushPolicy.remainingMinimumWait(elapsed: .milliseconds(50)) == .zero)
        #expect(QuitStorageFlushPolicy.remainingMinimumWait(elapsed: .milliseconds(480)) == .zero)
    }

    @Test
    func selectionSkipsNonPersistentStoresAndDuplicates() {
        let shared = UUID()
        let other = UUID()
        let candidates = [
            Store(name: "a", id: shared, isPersistent: true),
            Store(name: "preview", id: nil, isPersistent: false),
            Store(name: "b", id: shared, isPersistent: true),
            Store(name: "c", id: other, isPersistent: true),
            Store(name: "preview2", id: nil, isPersistent: false),
        ]

        let selected = QuitStorageFlushPolicy.storesToFlush(
            candidates, identifier: \.id, isPersistent: \.isPersistent
        )

        #expect(selected.map(\.name) == ["a", "c"])
    }

    @Test
    func selectionOfOnlyNonPersistentStoresIsEmpty() {
        let selected = QuitStorageFlushPolicy.storesToFlush(
            [Store(name: "preview", id: nil, isPersistent: false)],
            identifier: \.id, isPersistent: \.isPersistent
        )
        #expect(selected.isEmpty)
    }

    @Test
    func millisecondsTruncateToWholeValues() {
        #expect(QuitStorageFlushPolicy.milliseconds(.milliseconds(1_234)) == 1_234)
        #expect(QuitStorageFlushPolicy.milliseconds(.microseconds(15_900)) == 15)
        #expect(QuitStorageFlushPolicy.milliseconds(.zero) == 0)
    }

    @Test
    func onlyChatAppTeardownsOtherThanQuitAreLogged() {
        for reason in WebViewTeardownReason.allCases {
            #expect(!WebViewTeardownReason.isLogged(reason, isChatApp: false))
            #expect(WebViewTeardownReason.isLogged(reason, isChatApp: true) == (reason != .quit))
        }
    }

    @Test
    func newWebViewReasonPrefersHibernationThenRebuild() {
        #expect(AppInitiatedNavigationReason.forNewWebView(wasHibernated: true, wasRebuilt: true) == .wakeFromHibernation)
        #expect(AppInitiatedNavigationReason.forNewWebView(wasHibernated: false, wasRebuilt: true) == .rebuild)
        #expect(AppInitiatedNavigationReason.forNewWebView(wasHibernated: false, wasRebuilt: false) == .initialLoad)
    }

    /// The log lines promise fixed strings. A rename would break saved
    /// `log show` filters, so the values stay stable.
    @Test
    func reasonStringsAreStable() {
        #expect(WebViewTeardownReason.allCases.map(\.rawValue) == [
            "idleHibernation", "capacityEviction", "manualHibernation", "rebuild", "removal", "quit",
        ])
        #expect(AppInitiatedNavigationReason.errorPageRetry.rawValue == "errorPageRetry")
        #expect(AppInitiatedNavigationReason.wakeFromHibernation.rawValue == "wakeFromHibernation")
    }
}
