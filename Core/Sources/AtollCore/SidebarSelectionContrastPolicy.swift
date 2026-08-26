/// Selects the readable sidebar label treatment for shell transparency.
public enum SidebarSelectionContrastPolicy {
    public static let highContrastTextThreshold = 0.6

    public static func usesHighContrastText(shellTransparency: Double) -> Bool {
        normalized(shellTransparency) >= highContrastTextThreshold
    }

    private static func normalized(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
