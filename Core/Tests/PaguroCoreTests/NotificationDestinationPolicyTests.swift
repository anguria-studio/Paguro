import Foundation
import Testing
@testable import PaguroCore

struct NotificationDestinationPolicyTests {
    private let serviceURL = URL(string: "https://app.slack.com/client/home")!

    @Test
    func acceptsOwnedAbsoluteAndRelativeWebDestinations() {
        let cases: [(String, String)] = [
            (
                "https://app.slack.com/client/team/channel?thread=1#reply",
                "https://app.slack.com/client/team/channel?thread=1#reply"
            ),
            (
                "https://workspace.slack.com/archives/general",
                "https://workspace.slack.com/archives/general"
            ),
            (
                "/client/team/direct-message",
                "https://app.slack.com/client/team/direct-message"
            ),
        ]

        for (rawValue, expected) in cases {
            #expect(
                NotificationDestinationPolicy.approvedURL(
                    rawValue,
                    serviceURL: serviceURL
                )?.absoluteString == expected
            )
        }
    }

    @Test
    func rejectsUnsafeOrForeignDestinations() {
        let cases = [
            "https://example.com/messages/1",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "https://person:secret@app.slack.com/client",
            "https://app.slack.com/line\nbreak",
            "",
        ]

        for rawValue in cases {
            #expect(NotificationDestinationPolicy.approvedURL(
                rawValue,
                serviceURL: serviceURL
            ) == nil)
        }
    }

    @Test
    func keepsSharedUmbrellaProductsSeparate() {
        let gmail = URL(string: "https://mail.google.com/mail/u/0/")!

        #expect(NotificationDestinationPolicy.approvedURL(
            "https://mail.google.com/mail/u/0/#inbox/message",
            serviceURL: gmail
        ) != nil)
        #expect(NotificationDestinationPolicy.approvedURL(
            "https://docs.google.com/document/d/1",
            serviceURL: gmail
        ) == nil)
    }

    @Test
    func rejectsAnOversizedDestinationBeforeResolution() {
        let rawValue = "/" + String(
            repeating: "x",
            count: NotificationDestinationPolicy.maximumURLBytes
        )

        #expect(NotificationDestinationPolicy.approvedURL(
            rawValue,
            serviceURL: serviceURL
        ) == nil)
    }

    @Test
    func navigationRequestCanKeepOrOmitADestination() {
        let serviceID = UUID()
        let targetURL = URL(string: "https://app.slack.com/client/team/channel")!
        let pageClickToken = UUID()

        #expect(NotificationNavigationRequest(
            serviceID: serviceID,
            targetURL: targetURL,
            pageClickToken: pageClickToken
        ) == NotificationNavigationRequest(
            serviceID: serviceID,
            targetURLString: targetURL.absoluteString,
            pageClickToken: pageClickToken
        ))
        #expect(NotificationNavigationRequest(
            serviceID: serviceID,
            targetURL: nil
        ).targetURLString == nil)
    }
}
