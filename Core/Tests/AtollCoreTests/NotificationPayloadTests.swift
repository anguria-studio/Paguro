import Foundation
import Testing
@testable import AtollCore

struct NotificationPayloadTests {
    @Test
    func validPayloadDecodesAndRemovesNonDisplayControls() throws {
        let json = #"{"title":"New\u0000 message","body":"Line 1\nLine 2","icon":"https://example.com/icon.png","tag":"message-1","serviceID":"service-1"}"#

        let payload = try NotificationPayload.decode(json)

        #expect(payload == NotificationPayload(
            title: "New message",
            body: "Line 1\nLine 2",
            icon: "https://example.com/icon.png",
            tag: "message-1",
            serviceID: "service-1"
        ))
    }

    @Test
    func invalidPayloadTable() {
        let validFields = #""body":"","icon":"","tag":"","serviceID":"service-1""#
        let cases: [(name: String, json: String, error: NotificationPayloadDecodeError)] = [
            ("malformed JSON", "{", .invalidJSON),
            ("missing title", "{\(validFields)}", .missingField("title")),
            ("wrong title type", "{\"title\":12,\(validFields)}", .invalidField("title")),
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
                "over-long icon",
                Self.payloadJSON(icon: String(
                    repeating: "x",
                    count: NotificationPayload.maximumIconBytes + 1
                )),
                .fieldTooLong(
                    field: "icon",
                    maximumBytes: NotificationPayload.maximumIconBytes
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
                "over-long service ID",
                Self.payloadJSON(serviceID: String(
                    repeating: "x",
                    count: NotificationPayload.maximumServiceIDBytes + 1
                )),
                .fieldTooLong(
                    field: "serviceID",
                    maximumBytes: NotificationPayload.maximumServiceIDBytes
                )
            ),
        ]

        for item in cases {
            #expect(throws: item.error, Comment(rawValue: item.name)) {
                try NotificationPayload.decode(item.json)
            }
        }
    }

    private static func payloadJSON(
        title: String = "Title",
        body: String = "Body",
        icon: String = "",
        tag: String = "",
        serviceID: String = "service-1"
    ) -> String {
        let object = [
            "title": title,
            "body": body,
            "icon": icon,
            "tag": tag,
            "serviceID": serviceID,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
