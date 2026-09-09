import Foundation

/// Normalizes the optional emoji that can accompany a workspace name.
public enum WorkspaceEmoji {
    /// Returns the visible emoji, or `nil` when the stored value is empty.
    public static func displayValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns the migration-safe value to store in the existing string field.
    public static func storedValue(_ value: String) -> String {
        displayValue(value) ?? ""
    }

    /// Joins an optional emoji and workspace name without leading whitespace.
    public static func label(name: String, emoji: String) -> String {
        guard let emoji = displayValue(emoji) else { return name }
        return "\(emoji) \(name)"
    }
}
