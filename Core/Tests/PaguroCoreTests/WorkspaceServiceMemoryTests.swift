import PaguroCore
import Testing
import Foundation

@Suite("Workspace service memory")
struct WorkspaceServiceMemoryTests {
    private let workspace = UUID()
    private let otherWorkspace = UUID()
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    private var members: [UUID] { [first, second, third] }

    @Test("A workspace opens the service it was left on")
    func aWorkspaceOpensTheServiceItWasLeftOn() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)

        #expect(memory.serviceToOpen(
            in: workspace,
            memberServiceIDs: members,
            currentServiceID: nil
        ) == second)
    }

    @Test("A workspace with nothing remembered opens its first service")
    func aWorkspaceWithNothingRememberedOpensItsFirst() {
        let memory = WorkspaceServiceMemory()

        #expect(memory.serviceToOpen(
            in: workspace,
            memberServiceIDs: members,
            currentServiceID: nil
        ) == first)
    }

    @Test("A remembered service that left the workspace is not opened")
    func aRememberedServiceThatLeftIsNotOpened() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)

        #expect(memory.serviceToOpen(
            in: workspace,
            memberServiceIDs: [first, third],
            currentServiceID: nil
        ) == first)
    }

    @Test("A service chosen in the same step keeps its place")
    func aServiceChosenInTheSameStepKeepsItsPlace() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)

        #expect(memory.serviceToOpen(
            in: workspace,
            memberServiceIDs: members,
            currentServiceID: third
        ) == third)
    }

    @Test("A service from another workspace does not keep its place")
    func aServiceFromAnotherWorkspaceDoesNotKeepItsPlace() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)
        let outsider = UUID()

        #expect(memory.serviceToOpen(
            in: workspace,
            memberServiceIDs: members,
            currentServiceID: outsider
        ) == second)
    }

    @Test("Each workspace remembers its own service")
    func eachWorkspaceRemembersItsOwn() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)
        memory.remember(serviceID: third, in: otherWorkspace)

        #expect(memory.lastService(in: workspace) == second)
        #expect(memory.lastService(in: otherWorkspace) == third)
    }

    @Test("An empty workspace opens nothing")
    func anEmptyWorkspaceOpensNothing() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)

        #expect(memory.serviceToOpen(
            in: workspace,
            memberServiceIDs: [],
            currentServiceID: nil
        ) == nil)
    }

    @Test("A workspace that is gone is forgotten")
    func aWorkspaceThatIsGoneIsForgotten() {
        var memory = WorkspaceServiceMemory()
        memory.remember(serviceID: second, in: workspace)
        memory.forget(workspaceID: workspace)

        #expect(memory.lastService(in: workspace) == nil)
        #expect(memory.stored.isEmpty)
    }
}
