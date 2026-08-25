/// Decides whether the workspace switcher adds useful navigation.
public enum SpaceSwitcherVisibility {
    /// Keep the control for zero or multiple spaces. Hide it when there is
    /// exactly one space because there is nothing to switch.
    public static func showsSwitcher(spaceCount: Int) -> Bool {
        spaceCount != 1
    }
}
