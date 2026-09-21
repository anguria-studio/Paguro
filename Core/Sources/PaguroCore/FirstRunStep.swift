/// Navigation changes the setup page, never the saved workspace.
public enum FirstRunStep: Int, CaseIterable, Sendable {
    case welcome = 1
    case workspace
    case appearance

    public func canNavigate(to destination: Self, canCreateWorkspace: Bool) -> Bool {
        guard destination != self else { return false }
        return destination != .appearance || canCreateWorkspace
    }
}
