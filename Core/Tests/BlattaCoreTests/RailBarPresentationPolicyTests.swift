import BlattaCore
import Testing

@Suite("Rail bar presentation policy")
struct RailBarPresentationPolicyTests {
    private let policy = RailBarPresentationPolicy.self

    @Test("All workspaces groups the rail when a second workspace exists")
    func allWorkspacesGroupsTheRail() {
        #expect(policy.groupsByWorkspace(mode: .all, workspaceCount: 2))
        #expect(policy.groupsByWorkspace(mode: .all, workspaceCount: 9))
        #expect(!policy.groupsByWorkspace(mode: .all, workspaceCount: 1))
        #expect(!policy.groupsByWorkspace(mode: .all, workspaceCount: 0))
    }

    @Test("The current workspace mode never groups the rail")
    func currentWorkspaceModeNeverGroups() {
        #expect(!policy.groupsByWorkspace(mode: .current, workspaceCount: 5))
    }

    @Test("Icons only is offered for the top bar in both workspace views")
    func iconsOnlyIsOfferedForTheTopBar() {
        #expect(policy.offersIconsOnly(isTopBar: true))
        #expect(!policy.offersIconsOnly(isTopBar: false))
    }

    @Test("A stored icons-only value applies only where it is offered")
    func storedIconsOnlyAppliesOnlyWhereOffered() {
        #expect(policy.showsIconsOnly(isTopBar: true, iconsOnlyPreference: true))
        #expect(!policy.showsIconsOnly(isTopBar: true, iconsOnlyPreference: false))
        // The sidebar keeps its names even after the top bar turned this on.
        #expect(!policy.showsIconsOnly(isTopBar: false, iconsOnlyPreference: true))
    }
}
