import PaguroCore

extension MediaPermissionPolicy {
    var displayName: String {
        switch self {
        case .ask: return "Ask"
        case .allow: return "Allow"
        case .deny: return "Deny"
        }
    }
}
