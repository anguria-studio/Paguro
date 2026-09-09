import Testing
@testable import PaguroCore

struct WorkspaceDeletionPolicyTests {
    @Test
    func deletingAWorkspaceFindsServicesThatExistOnlyThere() {
        let memberships: [String: Set<String>] = [
            "only-here": ["work"],
            "also-elsewhere": ["work", "personal"],
            "elsewhere": ["personal"],
        ]

        #expect(WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: "work",
            memberships: memberships
        ) == ["only-here"])
    }

    @Test
    func absentWorkspaceAndEmptyMembershipsOrphanNothing() {
        #expect(WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: "work",
            memberships: ["service": ["personal"]]
        ).isEmpty)
        #expect(WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: "work",
            memberships: [String: Set<String>]()
        ).isEmpty)
    }
}
