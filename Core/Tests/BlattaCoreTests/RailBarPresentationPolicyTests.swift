import BlattaCore
import Testing

@Suite("Rail bar presentation policy")
struct RailBarPresentationPolicyTests {
    private let policy = RailBarPresentationPolicy.self

    @Test("All workspaces groups the rail when a second workspace exists")
    func allWorkspacesGroupsTheRail() {
        #expect(policy.groupsByWorkspace(mode: .all, workspaceCount: 2, hasWorkspaceRail: false))
        #expect(policy.groupsByWorkspace(mode: .all, workspaceCount: 9, hasWorkspaceRail: false))
        #expect(!policy.groupsByWorkspace(mode: .all, workspaceCount: 1, hasWorkspaceRail: false))
        #expect(!policy.groupsByWorkspace(mode: .all, workspaceCount: 0, hasWorkspaceRail: false))
    }

    @Test("The current workspace mode never groups the rail")
    func currentWorkspaceModeNeverGroups() {
        #expect(!policy.groupsByWorkspace(mode: .current, workspaceCount: 5, hasWorkspaceRail: false))
    }

    @Test("A workspace rail replaces the grouping and the setting behind it")
    func aWorkspaceRailReplacesTheGrouping() {
        #expect(!policy.groupsByWorkspace(mode: .all, workspaceCount: 5, hasWorkspaceRail: true))
        #expect(!policy.offersWorkspaceView(hasWorkspaceRail: true))
        #expect(policy.offersWorkspaceView(hasWorkspaceRail: false))
    }

    @Test("Icons only is offered while the services are in the bar")
    func iconsOnlyIsOfferedForTheServiceBar() {
        #expect(policy.offersIconsOnly(servicesInBar: true))
        #expect(!policy.offersIconsOnly(servicesInBar: false))
    }

    @Test("A stored icons-only value applies only where it is offered")
    func storedIconsOnlyAppliesOnlyWhereOffered() {
        #expect(policy.showsIconsOnly(servicesInBar: true, iconsOnlyPreference: true))
        #expect(!policy.showsIconsOnly(servicesInBar: true, iconsOnlyPreference: false))
        // A service rail on the left keeps its names, whatever the bar stored.
        #expect(!policy.showsIconsOnly(servicesInBar: false, iconsOnlyPreference: true))
    }

    @Test("Only the collapsed workspace rail falls back to a default icon")
    func onlyTheCollapsedWorkspaceRailFallsBack() {
        #expect(policy.showsWorkspaceFallbackIcon(emoji: "", isIconOnlyWorkspaceRail: true))
        #expect(policy.showsWorkspaceFallbackIcon(emoji: "  ", isIconOnlyWorkspaceRail: true))
        // A workspace with an emoji has its own icon already.
        #expect(!policy.showsWorkspaceFallbackIcon(emoji: "🏠", isIconOnlyWorkspaceRail: true))
        // Every other rail keeps an emoji-less workspace as its name alone.
        #expect(!policy.showsWorkspaceFallbackIcon(emoji: "", isIconOnlyWorkspaceRail: false))
    }
}
