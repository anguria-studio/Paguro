import Foundation

public enum NotificationIslandFocusRule {
    /// Keeps the reading position after dismissal, using the previous card at the end.
    public static func replacement(for dismissedID: UUID, in eventIDs: [UUID]) -> UUID? {
        guard let index = eventIDs.firstIndex(of: dismissedID) else { return nil }
        if index + 1 < eventIDs.count { return eventIDs[index + 1] }
        return index > 0 ? eventIDs[index - 1] : nil
    }
}
