import Foundation
import Testing
@testable import AtollCore

struct NavigationDecisionTests {
    @Test
    func decisionTable() {
        let cases: [(
            name: String,
            request: NavigationRequestContext,
            expected: NavigationDecision
        )] = [
            ("missing URL", request(url: nil), .cancel),
            ("same-service page", request(url: "https://app.slack.com/client"), .allow),
            ("HTTP page", request(url: "http://app.slack.com/client"), .allow),
            ("about page", request(url: "about:blank"), .allow),
            ("blob page", request(url: "blob:https://app.slack.com/id"), .allow),
            ("data page", request(url: "data:text/plain,hello"), .allow),
            ("clicked mail link", request(
                url: "mailto:person@example.com",
                isLinkActivated: true
            ), .openExternally(.system)),
            ("clicked telephone link", request(
                url: "tel:+15551234",
                isLinkActivated: true
            ), .openExternally(.system)),
            ("programmatic mail link", request(
                url: "mailto:person@example.com"
            ), .cancel),
            ("unsafe clicked scheme", request(
                url: "smb://attacker.example/share",
                isLinkActivated: true
            ), .cancel),
            ("clicked file URL", request(
                url: "file:///etc/passwd",
                isLinkActivated: true
            ), .cancel),
            ("programmatic app scheme", request(
                url: "slack://channel/general"
            ), .cancel),
            ("cross-service download", request(
                url: "https://files.example/report.pdf",
                isLinkActivated: true,
                shouldDownload: true
            ), .download),
            ("Command-click download", request(
                url: "https://app.slack.com/report.pdf",
                isLinkActivated: true,
                shouldDownload: true,
                hasCommandModifier: true
            ), .download),
            ("same-service Command-click", request(
                url: "https://app.slack.com/thread",
                isLinkActivated: true,
                hasCommandModifier: true
            ), .openExternally(.system)),
            ("cross-service main-frame click", request(
                url: "https://example.com/article",
                isLinkActivated: true
            ), .openExternally(.matchingServiceOrSystem)),
            ("cross-service subframe click", request(
                url: "https://example.com/frame",
                isLinkActivated: true,
                targetsMainFrame: false
            ), .allow),
            ("programmatic cross-service navigation", request(
                url: "https://example.com/redirect"
            ), .allow),
            ("authentication click", request(
                url: "https://accounts.google.com/signin",
                isLinkActivated: true,
                currentHost: "mail.google.com"
            ), .allow),
            ("same service sibling host", request(
                url: "https://workspace.slack.com/client",
                isLinkActivated: true
            ), .allow),
            ("separate Google product", request(
                url: "https://docs.google.com/document",
                isLinkActivated: true,
                currentHost: "mail.google.com"
            ), .openExternally(.matchingServiceOrSystem)),
        ]

        for item in cases {
            #expect(
                NavigationDecision.decide(item.request) == item.expected,
                Comment(rawValue: item.name)
            )
        }
    }

    private func request(
        url: String?,
        isLinkActivated: Bool = false,
        shouldDownload: Bool = false,
        hasCommandModifier: Bool = false,
        targetsMainFrame: Bool = true,
        currentHost: String? = "app.slack.com"
    ) -> NavigationRequestContext {
        NavigationRequestContext(
            url: url.flatMap(URL.init(string:)),
            isLinkActivated: isLinkActivated,
            shouldDownload: shouldDownload,
            hasCommandModifier: hasCommandModifier,
            targetsMainFrame: targetsMainFrame,
            currentHost: currentHost
        )
    }
}
