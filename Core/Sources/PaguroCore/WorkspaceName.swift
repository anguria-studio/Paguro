import Foundation

/// Names entered during setup must contain visible text.
public enum WorkspaceName {
    public static let defaultValue = "Personal"

    public static func normalized(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
