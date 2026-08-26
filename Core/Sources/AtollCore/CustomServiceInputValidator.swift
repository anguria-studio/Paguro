import Foundation

/// The normalized result of validating custom service input.
public enum CustomServiceInputValidation: Equatable, Sendable {
    case valid(label: String, url: String)
    case invalid(String)
}

/// Pure validation and normalization for a custom service.
public enum CustomServiceInputValidator {
    public static func validate(
        label rawLabel: String,
        url rawURL: String
    ) -> CustomServiceInputValidation {
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            return .invalid("Label can't be empty")
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return .invalid("URL must start with https:// or http://")
        }

        guard let host = components.host, !host.isEmpty else {
            return .invalid("URL must include a host")
        }

        var normalizedComponents = components
        normalizedComponents.scheme = scheme
        guard let url = normalizedComponents.url else {
            return .invalid("That doesn't look like a valid URL")
        }

        return .valid(label: label, url: url.absoluteString)
    }
}
