import Foundation
import Testing
@testable import PaguroCore

struct NotificationPayloadTests {
    @Test
    func validPayloadDecodesAndRemovesNonDisplayControls() throws {
        let json = #"{"version":1,"type":"web-notification","title":"New\u0000 message","body":"Line 1\nLine 2","tag":"message-1","targetURL":"/messages/1"}"#

        let payload = try NotificationPayload.decode(json)

        #expect(payload == NotificationPayload(
            title: "New message",
            body: "Line 1\nLine 2",
            tag: "message-1",
            targetURL: "/messages/1"
        ))
    }

    @Test
    func missingOptionalTextFieldsDecodeAsEmptyStrings() throws {
        let payload = try NotificationPayload.decode(
            #"{"version":1,"type":"web-notification","title":"New message"}"#
        )

        #expect(payload.body.isEmpty)
        #expect(payload.tag.isEmpty)
        #expect(payload.targetURL.isEmpty)
        #expect(payload.pageClickToken.isEmpty)
        #expect(payload.probe == nil)
    }

    @Test
    func decodesAValidatedPageClickToken() throws {
        let token = "33333333-3333-4333-8333-333333333333"
        let payload = try NotificationPayload.decode(
            Self.payloadJSON(pageClickToken: token)
        )

        #expect(payload.pageClickToken == token)
    }

    @Test
    func decodesPrivacyLimitedProbeMetadata() throws {
        let payload = try NotificationPayload.decode(
            #"{"version":1,"type":"web-notification","title":"New message","probe":{"source":"constructor","dataShape":"{channelId:string,teamId:string}"}}"#
        )

        #expect(payload.probe == NotificationProbeMetadata(
            source: .constructor,
            dataShape: "{channelId:string,teamId:string}"
        ))
    }

    @Test
    func ignoresIdentityAndIconFieldsFromThePage() throws {
        let json = #"{"version":1,"type":"web-notification","title":"New message","serviceID":"spoofed-service","icon":"https://untrusted.example/icon.png"}"#

        let payload = try NotificationPayload.decode(json)

        #expect(payload == NotificationPayload(title: "New message"))
    }

    @Test
    func preservesEmojiSequencesAndRightToLeftMarks() throws {
        let title = "👨‍👩‍👧 Family"
        let body = "\u{200F}مرحبا"

        let payload = try NotificationPayload.decode(Self.payloadJSON(
            title: title,
            body: body
        ))

        #expect(payload.title == title)
        #expect(payload.body == body)
    }

    @Test
    func invalidPayloadTable() {
        let validFields = #""version":1,"type":"web-notification","body":"","tag":"""#
        let cases: [(name: String, json: String, error: NotificationPayloadDecodeError)] = [
            ("malformed JSON", "{", .invalidJSON),
            ("missing title", "{\(validFields)}", .missingField("title")),
            ("wrong title type", "{\"title\":12,\(validFields)}", .invalidField("title")),
            (
                "missing version",
                #"{"type":"web-notification","title":"Title"}"#,
                .missingField("version")
            ),
            (
                "wrong version type",
                #"{"version":"1","type":"web-notification","title":"Title"}"#,
                .invalidField("version")
            ),
            (
                "unsupported version",
                Self.payloadJSON(version: NotificationPayload.currentVersion + 1),
                .unsupportedVersion(NotificationPayload.currentVersion + 1)
            ),
            (
                "missing type",
                #"{"version":1,"title":"Title"}"#,
                .missingField("type")
            ),
            (
                "unsupported type",
                Self.payloadJSON(type: "unknown"),
                .unsupportedType("unknown")
            ),
            (
                "wrong target URL type",
                #"{"version":1,"type":"web-notification","title":"Title","targetURL":12}"#,
                .invalidField("targetURL")
            ),
            (
                "invalid page click token",
                #"{"version":1,"type":"web-notification","title":"Title","pageClickToken":"not-a-uuid"}"#,
                .invalidField("pageClickToken")
            ),
            (
                "unknown probe source",
                #"{"version":1,"type":"web-notification","title":"Title","probe":{"source":"worker","dataShape":"object"}}"#,
                .invalidField("probe.source")
            ),
            (
                "probe shape contains a control character",
                #"{"version":1,"type":"web-notification","title":"Title","probe":{"source":"constructor","dataShape":"line\nvalue"}}"#,
                .invalidField("probe.dataShape")
            ),
            (
                "over-long title",
                Self.payloadJSON(title: String(
                    repeating: "é",
                    count: NotificationPayload.maximumTitleBytes / 2 + 1
                )),
                .fieldTooLong(
                    field: "title",
                    maximumBytes: NotificationPayload.maximumTitleBytes
                )
            ),
            (
                "over-long body",
                Self.payloadJSON(body: String(
                    repeating: "x",
                    count: NotificationPayload.maximumBodyBytes + 1
                )),
                .fieldTooLong(
                    field: "body",
                    maximumBytes: NotificationPayload.maximumBodyBytes
                )
            ),
            (
                "over-long tag",
                Self.payloadJSON(tag: String(
                    repeating: "x",
                    count: NotificationPayload.maximumTagBytes + 1
                )),
                .fieldTooLong(
                    field: "tag",
                    maximumBytes: NotificationPayload.maximumTagBytes
                )
            ),
            (
                "over-long target URL",
                Self.payloadJSON(targetURL: String(
                    repeating: "x",
                    count: NotificationPayload.maximumTargetURLBytes + 1
                )),
                .fieldTooLong(
                    field: "targetURL",
                    maximumBytes: NotificationPayload.maximumTargetURLBytes
                )
            ),
            (
                "over-long probe shape",
                Self.payloadJSON(
                    probe: [
                        "source": NotificationProbeSource.constructor.rawValue,
                        "dataShape": String(
                            repeating: "x",
                            count: NotificationPayload.maximumProbeShapeBytes + 1
                        ),
                    ]
                ),
                .fieldTooLong(
                    field: "probe.dataShape",
                    maximumBytes: NotificationPayload.maximumProbeShapeBytes
                )
            ),
        ]

        for item in cases {
            #expect(throws: item.error, Comment(rawValue: item.name)) {
                try NotificationPayload.decode(item.json)
            }
        }
    }

    @Test
    func rejectsAnOversizedMessageBeforeItDecodesUnknownFields() {
        let object: [String: Any] = [
            "version": NotificationPayload.currentVersion,
            "type": NotificationPayloadType.webNotification.rawValue,
            "title": "Title",
            "padding": String(
                repeating: "x",
                count: NotificationPayload.maximumMessageBytes
            ),
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)

        #expect(throws: NotificationPayloadDecodeError.messageTooLong(
            maximumBytes: NotificationPayload.maximumMessageBytes
        )) {
            try NotificationPayload.decode(json)
        }
    }

    private static func payloadJSON(
        version: Int = NotificationPayload.currentVersion,
        type: String = NotificationPayloadType.webNotification.rawValue,
        title: String = "Title",
        body: String = "Body",
        tag: String = "",
        targetURL: String = "",
        pageClickToken: String = "",
        probe: [String: String]? = nil
    ) -> String {
        var object: [String: Any] = [
            "version": version,
            "type": type,
            "title": title,
            "body": body,
            "tag": tag,
            "targetURL": targetURL,
            "pageClickToken": pageClickToken,
        ]
        object["probe"] = probe
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
