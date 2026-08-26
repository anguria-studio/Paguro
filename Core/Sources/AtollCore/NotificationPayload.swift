import Foundation

/// A validated notification message from a web service.
public struct NotificationPayload: Equatable, Sendable {
    public static let maximumTitleBytes = 512
    public static let maximumBodyBytes = 4_096
    public static let maximumIconBytes = 2_048
    public static let maximumTagBytes = 512
    public static let maximumServiceIDBytes = 64

    public let title: String
    public let body: String
    public let icon: String
    public let tag: String
    public let serviceID: String

    public init(
        title: String,
        body: String,
        icon: String,
        tag: String,
        serviceID: String
    ) {
        self.title = title
        self.body = body
        self.icon = icon
        self.tag = tag
        self.serviceID = serviceID
    }

    /// Decodes and validates one untrusted bridge message.
    public static func decode(_ json: String) throws -> NotificationPayload {
        let raw: RawPayload
        do {
            raw = try JSONDecoder().decode(RawPayload.self, from: Data(json.utf8))
        } catch DecodingError.keyNotFound(let key, _) {
            throw NotificationPayloadDecodeError.missingField(key.stringValue)
        } catch DecodingError.typeMismatch(_, let context) {
            throw NotificationPayloadDecodeError.invalidField(
                context.codingPath.last?.stringValue ?? "payload"
            )
        } catch DecodingError.valueNotFound(_, let context) {
            throw NotificationPayloadDecodeError.invalidField(
                context.codingPath.last?.stringValue ?? "payload"
            )
        } catch {
            throw NotificationPayloadDecodeError.invalidJSON
        }

        try validate(raw.title, field: "title", maximumBytes: maximumTitleBytes)
        try validate(raw.body, field: "body", maximumBytes: maximumBodyBytes)
        try validate(raw.icon, field: "icon", maximumBytes: maximumIconBytes)
        try validate(raw.tag, field: "tag", maximumBytes: maximumTagBytes)
        try validate(raw.serviceID, field: "serviceID", maximumBytes: maximumServiceIDBytes)

        return NotificationPayload(
            title: removingNonDisplayControls(from: raw.title),
            body: removingNonDisplayControls(from: raw.body),
            icon: removingNonDisplayControls(from: raw.icon),
            tag: removingNonDisplayControls(from: raw.tag),
            serviceID: removingNonDisplayControls(from: raw.serviceID)
        )
    }

    private static func validate(
        _ value: String,
        field: String,
        maximumBytes: Int
    ) throws {
        guard value.utf8.count <= maximumBytes else {
            throw NotificationPayloadDecodeError.fieldTooLong(
                field: field,
                maximumBytes: maximumBytes
            )
        }
    }

    private static func removingNonDisplayControls(from value: String) -> String {
        let permittedControls: Set<Unicode.Scalar> = ["\t", "\n"]
        return String(value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                || permittedControls.contains(scalar)
        })
    }

    private struct RawPayload: Decodable {
        let title: String
        let body: String
        let icon: String
        let tag: String
        let serviceID: String
    }
}

/// Why an untrusted notification payload could not be decoded.
public enum NotificationPayloadDecodeError: Error, Equatable, Sendable {
    case invalidJSON
    case missingField(String)
    case invalidField(String)
    case fieldTooLong(field: String, maximumBytes: Int)
}

extension NotificationPayloadDecodeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The payload is not valid JSON."
        case .missingField(let field):
            return "The payload is missing the \(field) field."
        case .invalidField(let field):
            return "The payload has an invalid \(field) field."
        case .fieldTooLong(let field, let maximumBytes):
            return "The payload \(field) field exceeds \(maximumBytes) bytes."
        }
    }
}
