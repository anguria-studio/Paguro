import Foundation

/// A validated notification message from a web service.
public struct NotificationPayload: Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumMessageBytes = 16_384
    public static let maximumTitleBytes = 512
    public static let maximumBodyBytes = 4_096
    public static let maximumTagBytes = 512
    public static let maximumTargetURLBytes = 4_096
    public static let maximumPageClickTokenBytes = 36
    public static let maximumProbeShapeBytes = 2_048

    public let version: Int
    public let type: NotificationPayloadType
    public let title: String
    public let body: String
    public let tag: String
    public let targetURL: String
    public let pageClickToken: String
    public let probe: NotificationProbeMetadata?

    public init(
        version: Int = currentVersion,
        type: NotificationPayloadType = .webNotification,
        title: String,
        body: String = "",
        tag: String = "",
        targetURL: String = "",
        pageClickToken: String = "",
        probe: NotificationProbeMetadata? = nil
    ) {
        self.version = version
        self.type = type
        self.title = title
        self.body = body
        self.tag = tag
        self.targetURL = targetURL
        self.pageClickToken = pageClickToken
        self.probe = probe
    }

    /// Decodes and validates one untrusted bridge message.
    public static func decode(_ json: String) throws -> NotificationPayload {
        guard json.utf8.count <= maximumMessageBytes else {
            throw NotificationPayloadDecodeError.messageTooLong(
                maximumBytes: maximumMessageBytes
            )
        }

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

        guard raw.version == currentVersion else {
            throw NotificationPayloadDecodeError.unsupportedVersion(raw.version)
        }
        guard let type = NotificationPayloadType(rawValue: raw.type) else {
            throw NotificationPayloadDecodeError.unsupportedType(raw.type)
        }

        try validate(raw.title, field: "title", maximumBytes: maximumTitleBytes)
        try validate(raw.body, field: "body", maximumBytes: maximumBodyBytes)
        try validate(raw.tag, field: "tag", maximumBytes: maximumTagBytes)
        try validate(
            raw.targetURL,
            field: "targetURL",
            maximumBytes: maximumTargetURLBytes
        )
        try validate(
            raw.pageClickToken,
            field: "pageClickToken",
            maximumBytes: maximumPageClickTokenBytes
        )
        guard raw.pageClickToken.isEmpty || UUID(uuidString: raw.pageClickToken) != nil else {
            throw NotificationPayloadDecodeError.invalidField("pageClickToken")
        }
        let probe: NotificationProbeMetadata?
        if let rawProbe = raw.probe {
            guard let source = NotificationProbeSource(rawValue: rawProbe.source) else {
                throw NotificationPayloadDecodeError.invalidField("probe.source")
            }
            try validate(
                rawProbe.dataShape,
                field: "probe.dataShape",
                maximumBytes: maximumProbeShapeBytes
            )
            guard rawProbe.dataShape.unicodeScalars.allSatisfy({
                (0x20...0x7E).contains($0.value)
            }) else {
                throw NotificationPayloadDecodeError.invalidField("probe.dataShape")
            }
            probe = NotificationProbeMetadata(
                source: source,
                dataShape: rawProbe.dataShape
            )
        } else {
            probe = nil
        }

        return NotificationPayload(
            version: raw.version,
            type: type,
            title: removingControlCharacters(from: raw.title),
            body: removingControlCharacters(from: raw.body),
            tag: removingControlCharacters(from: raw.tag),
            targetURL: raw.targetURL,
            pageClickToken: raw.pageClickToken,
            probe: probe
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

    private static func removingControlCharacters(from value: String) -> String {
        let permittedControls: Set<Unicode.Scalar> = ["\t", "\n"]
        return String(value.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .control
                || permittedControls.contains(scalar)
        })
    }

    private struct RawPayload: Decodable {
        let version: Int
        let type: String
        let title: String
        let body: String
        let tag: String
        let targetURL: String
        let pageClickToken: String
        let probe: RawProbe?

        private enum CodingKeys: String, CodingKey {
            case version
            case type
            case title
            case body
            case tag
            case targetURL
            case pageClickToken
            case probe
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            type = try container.decode(String.self, forKey: .type)
            title = try container.decode(String.self, forKey: .title)
            body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
            tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
            targetURL = try container.decodeIfPresent(String.self, forKey: .targetURL) ?? ""
            pageClickToken = try container.decodeIfPresent(
                String.self,
                forKey: .pageClickToken
            ) ?? ""
            probe = try container.decodeIfPresent(RawProbe.self, forKey: .probe)
        }
    }

    private struct RawProbe: Decodable {
        let source: String
        let dataShape: String
    }
}

/// A privacy-limited description from the opt-in provider probe.
public struct NotificationProbeMetadata: Equatable, Sendable {
    public let source: NotificationProbeSource
    public let dataShape: String

    public init(source: NotificationProbeSource, dataShape: String) {
        self.source = source
        self.dataShape = dataShape
    }
}

/// The page API that produced a probed notification.
public enum NotificationProbeSource: String, Equatable, Sendable {
    case constructor
    case serviceWorkerRegistration = "service-worker-registration"
}

/// The signal types that the notification bridge accepts.
public enum NotificationPayloadType: String, Equatable, Sendable {
    case webNotification = "web-notification"
}

/// Why an untrusted notification payload could not be decoded.
public enum NotificationPayloadDecodeError: Error, Equatable, Sendable {
    case invalidJSON
    case missingField(String)
    case invalidField(String)
    case messageTooLong(maximumBytes: Int)
    case unsupportedVersion(Int)
    case unsupportedType(String)
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
        case .messageTooLong(let maximumBytes):
            return "The payload exceeds \(maximumBytes) bytes."
        case .unsupportedVersion(let version):
            return "The payload version \(version) is not supported."
        case .unsupportedType:
            return "The payload type is not supported."
        case .fieldTooLong(let field, let maximumBytes):
            return "The payload \(field) field exceeds \(maximumBytes) bytes."
        }
    }
}
