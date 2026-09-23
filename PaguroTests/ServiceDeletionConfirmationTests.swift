import AppKit
import Observation
import SwiftData
import SwiftUI
import XCTest
@testable import Paguro

@MainActor
final class ServiceDeletionConfirmationTests: XCTestCase {
    func testDeleteButtonRemovesServiceFromPersistentStore() async throws {
        let fixture = try Fixture(testCase: self)
        defer { fixture.close() }
        fixture.state.pending = fixture.target
        let button = try await fixture.button(named: "Delete")
        button.performClick(nil)
        try await fixture.waitForDismissal()

        XCTAssertEqual(fixture.state.deletedIDs, [fixture.serviceID])
        XCTAssertNil(fixture.state.pending)
        let freshContext = ModelContext(fixture.container)
        XCTAssertEqual(try freshContext.fetch(FetchDescriptor<ServiceInstance>()).map(\.id),
                       [fixture.survivorID])
        XCTAssertEqual(try freshContext.fetchCount(FetchDescriptor<SpaceServiceLink>()), 1)
    }

    func testCancelKeepsServiceAndAllowsAnotherConfirmation() async throws {
        let fixture = try Fixture(testCase: self)
        defer { fixture.close() }
        fixture.state.pending = fixture.target
        let cancel = try await fixture.button(named: "Cancel")
        cancel.performClick(nil)
        try await fixture.waitForDismissal()
        XCTAssertTrue(fixture.state.deletedIDs.isEmpty)
        XCTAssertNil(fixture.state.pending)
        XCTAssertEqual(try fixture.container.mainContext.fetchCount(FetchDescriptor<ServiceInstance>()), 2)

        fixture.state.pending = fixture.target
        let delete = try await fixture.button(named: "Delete")
        delete.performClick(nil)
        try await fixture.waitForDismissal()
        XCTAssertEqual(fixture.state.deletedIDs, [fixture.serviceID])
    }

    @Observable
    @MainActor
    final class State {
        var pending: LiveSpaceServiceLink?
        var deletedIDs: [UUID] = []
    }

    private struct Host: View {
        @Bindable var state: State
        let store: WorkspaceStore

        var body: some View {
            Text("Service removal fixture")
                .frame(width: 400, height: 300)
                .deleteServiceConfirmation(link: $state.pending) { id in
                    do {
                        if try store.deleteService(id) != nil { state.deletedIDs.append(id) }
                    } catch {
                        XCTFail("Service deletion failed: \(error)")
                    }
                }
                // The rail also offers workspace deletion on its outer view.
                .confirmationDialog("Delete workspace?", isPresented: .constant(false)) {
                    Button("Delete", role: .destructive) {}
                }
        }
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let state = State()
        let window: NSWindow
        let target: LiveSpaceServiceLink
        let serviceID: UUID
        let survivorID: UUID
        let serviceLabel = "Removal fixture \(UUID().uuidString)"

        init(testCase: XCTestCase) throws {
            let sandbox = try StoreSandbox(testCase: testCase, label: "delete-confirmation")
            let schema = ModelFixtures.storeSchema
            container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: sandbox.storeURL)
            ])
            let context = container.mainContext
            let workspace = Space(name: "Personal")
            let service = ModelFixtures.service(label: serviceLabel, catalogID: nil)
            let survivor = ModelFixtures.service(label: "Keep", catalogID: nil)
            context.insert(workspace)
            context.insert(service)
            context.insert(survivor)
            let link = ModelFixtures.link(service, to: workspace, sortOrder: 0, in: context)
            ModelFixtures.link(survivor, to: workspace, sortOrder: 1, in: context)
            try context.save()
            target = try XCTUnwrap(LiveSpaceServiceLink(link))
            serviceID = service.id
            survivorID = survivor.id
            let store = WorkspaceStore(context: context, preferencesStore: PreferencesStore(context: context))
            window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Host(state: state, store: store))
            window.orderBack(nil)
        }

        func button(named title: String) async throws -> NSButton {
            for _ in 0..<150 {
                if let sheet = window.attachedSheet, let content = sheet.contentView,
                   let button = findButton(in: content, title: title) { return button }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw NSError(domain: "ServiceDeletionConfirmationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No native \(title) button appeared"])
        }

        private func findButton(in view: NSView, title: String) -> NSButton? {
            if let button = view as? NSButton, button.title == title { return button }
            return view.subviews.lazy.compactMap { self.findButton(in: $0, title: title) }.first
        }

        func waitForDismissal() async throws {
            for _ in 0..<150 {
                if window.attachedSheet == nil && state.pending == nil { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("The confirmation sheet did not dismiss")
        }

        func close() {
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
            window.close()
        }
    }
}
