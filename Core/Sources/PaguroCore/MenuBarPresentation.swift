/// Builds concise status text for the menu-bar window.
public enum MenuBarPresentation {
    public static func unreadSummary(_ count: Int) -> String {
        switch max(0, count) {
        case 0:
            "No unread notifications"
        case 1:
            "1 unread notification"
        case let count:
            "\(count) unread notifications"
        }
    }

    public static func serviceAccessibilityLabel(
        serviceStateLabel: String,
        workspaceName: String,
        isSelected: Bool
    ) -> String {
        var parts = [serviceStateLabel, "workspace \(workspaceName)"]
        if isSelected {
            parts.append("selected")
        }
        return parts.joined(separator: ", ")
    }
}
