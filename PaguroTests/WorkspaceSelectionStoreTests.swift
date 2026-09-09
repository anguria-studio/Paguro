import XCTest
import PaguroCore
@testable import Paguro

final class WorkspaceSelectionStoreTests: XCTestCase {
    @MainActor
    func testWhatAWorkspaceWasLeftOnSurvivesALaunch() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "workspace-selection")
        let workspace = UUID()
        let service = UUID()
        let other = UUID()

        var store = WorkspaceSelectionStore(defaults: sandbox.defaults)
        store.remember(serviceID: service, in: workspace)

        let reloaded = WorkspaceSelectionStore(defaults: sandbox.defaults)
        XCTAssertEqual(
            reloaded.serviceToOpen(
                in: workspace,
                memberServiceIDs: [other, service],
                currentServiceID: nil
            ),
            service
        )
    }

    @MainActor
    func testADeletedWorkspaceIsForgotten() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "workspace-selection-delete")
        let workspace = UUID()
        let service = UUID()

        var store = WorkspaceSelectionStore(defaults: sandbox.defaults)
        store.remember(serviceID: service, in: workspace)
        store.forget(workspaceID: workspace)

        let reloaded = WorkspaceSelectionStore(defaults: sandbox.defaults)
        XCTAssertNil(reloaded.memory.lastService(in: workspace))
    }

    /// The pairs are text in `UserDefaults`, so anything that no longer reads
    /// as a pair of identifiers is dropped rather than kept as a broken entry.
    @MainActor
    func testUnreadableStoredPairsAreDropped() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "workspace-selection-garbage")
        let workspace = UUID()
        let service = UUID()
        sandbox.defaults.set(
            [
                workspace.uuidString: service.uuidString,
                "not-an-identifier": service.uuidString,
                UUID().uuidString: "not-an-identifier",
            ],
            forKey: DefaultsKey.workspaceServiceMemory
        )

        let store = WorkspaceSelectionStore(defaults: sandbox.defaults)

        XCTAssertEqual(store.memory.stored, [workspace: service])
    }
}
