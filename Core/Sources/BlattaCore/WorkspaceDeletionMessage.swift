/// Builds the confirmation text for a workspace deletion.
///
/// Blatta deletes a service, and its sign-in data, only when the service
/// exists in no other workspace. The message must say this clearly, because
/// the deletion is not reversible.
public enum WorkspaceDeletionMessage {
    public static func text(orphanedServiceCount: Int) -> String {
        switch max(0, orphanedServiceCount) {
        case 0:
            return "No service will be deleted. Services that also belong to other workspaces stay available."
        case 1:
            return "1 service exists only in this workspace. Blatta will delete it and its sign-in data."
        default:
            return "\(orphanedServiceCount) services exist only in this workspace. Blatta will delete them and their sign-in data."
        }
    }
}
