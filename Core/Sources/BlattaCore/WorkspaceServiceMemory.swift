import Foundation

/// Which service a workspace opens on.
///
/// A workspace remembers the service that was last open in it, so returning to
/// a workspace returns to the work in it rather than to its first service. A
/// workspace with nothing remembered, or one whose remembered service has since
/// left it, opens its first service.
public struct WorkspaceServiceMemory: Equatable, Sendable {
    private var lastServiceByWorkspace: [UUID: UUID]

    public init(lastServiceByWorkspace: [UUID: UUID] = [:]) {
        self.lastServiceByWorkspace = lastServiceByWorkspace
    }

    public var stored: [UUID: UUID] {
        lastServiceByWorkspace
    }

    public func lastService(in workspaceID: UUID) -> UUID? {
        lastServiceByWorkspace[workspaceID]
    }

    public mutating func remember(serviceID: UUID, in workspaceID: UUID) {
        lastServiceByWorkspace[workspaceID] = serviceID
    }

    /// Drops a workspace that is gone. A workspace that comes back with the
    /// same identity is a different workspace to the person who made it.
    public mutating func forget(workspaceID: UUID) {
        lastServiceByWorkspace[workspaceID] = nil
    }

    /// The service to open in a workspace.
    ///
    /// A selection made in the same step wins: the quick switcher and the
    /// menu bar name a workspace and a service together, and this must not
    /// answer for the service they already chose.
    public func serviceToOpen(
        in workspaceID: UUID,
        memberServiceIDs: [UUID],
        currentServiceID: UUID?
    ) -> UUID? {
        let members = Set(memberServiceIDs)

        if let currentServiceID, members.contains(currentServiceID) {
            return currentServiceID
        }
        if let remembered = lastServiceByWorkspace[workspaceID], members.contains(remembered) {
            return remembered
        }
        return memberServiceIDs.first
    }
}
