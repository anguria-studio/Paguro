import Foundation

/// Identifies one service account in Atoll.
///
/// The type prevents code from using an unrelated UUID by mistake.
public struct ServiceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }
}
