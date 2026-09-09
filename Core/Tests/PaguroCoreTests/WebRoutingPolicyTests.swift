import Foundation
import XCTest
@testable import PaguroCore

final class WebRoutingPolicyTests: XCTestCase {
    func testServiceOwnership() {
        let cases: [(target: String, service: String, expected: Bool)] = [
            ("app.slack.com", "app.slack.com", true),
            ("myteam.slack.com", "app.slack.com", true),
            ("www.notion.so", "notion.so", true),
            ("APP.SLACK.COM", "app.slack.com", true),
            ("huddle.slack.com", "app.slack.com", true),
            ("docs.google.com", "mail.google.com", false),
            ("drive.google.com", "mail.google.com", false),
            ("mail.google.com", "mail.google.com", true),
            ("docs.google.com", "docs.google.com", true),
            ("accounts.google.com", "mail.google.com", false),
            ("evil.vercel.app", "team.vercel.app", false),
            ("attacker.github.io", "myproject.github.io", false),
            ("evil.pages.dev", "app.pages.dev", false),
            ("evil.workers.dev", "api.workers.dev", false),
            ("team.vercel.app", "team.vercel.app", true),
            ("app.team.vercel.app", "team.vercel.app", true),
            ("attacker.web.app", "alice.web.app", false),
            ("sub.alice.web.app", "alice.web.app", true),
            ("messenger.com", "facebook.com", false),
            ("notion.so", "mail.google.com", false),
            ("", "alice.web.app", false),
        ]

        for item in cases {
            XCTAssertEqual(
                WebRoutingPolicy.belongsToService(item.target, serviceHost: item.service),
                item.expected,
                "target=\(item.target), service=\(item.service)"
            )
        }
    }

    func testAuthenticationHosts() {
        for host in [
            "accounts.google.com",
            "login.microsoftonline.com",
            "appleid.apple.com",
            "ACCOUNTS.GOOGLE.COM",
            "eu.login.microsoftonline.com",
        ] {
            XCTAssertTrue(WebRoutingPolicy.isAuthenticationHost(host), host)
        }
        for host in [
            "mail.google.com",
            "docs.google.com",
            "portal.azure.com",
            "teams.cloud.microsoft",
            "example.com",
        ] {
            XCTAssertFalse(WebRoutingPolicy.isAuthenticationHost(host), host)
        }
    }

    func testNewWindowLoadsInPlaceOnlyForClickedSameServiceLinks() {
        XCTAssertTrue(WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: true,
            targetHost: "myteam.slack.com",
            openerHost: "app.slack.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: false,
            targetHost: "app.slack.com",
            openerHost: "app.slack.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: true,
            targetHost: "login.microsoftonline.com",
            openerHost: "teams.cloud.microsoft"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: true,
            targetHost: nil,
            openerHost: "app.slack.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: true,
            targetHost: "app.slack.com",
            openerHost: nil
        ))
    }

    func testPopupReloadAndCloseRules() {
        XCTAssertFalse(WebRoutingPolicy.shouldReloadOpener(
            selfClosed: false,
            openedAtAuthenticationHost: false
        ))
        XCTAssertTrue(WebRoutingPolicy.shouldReloadOpener(
            selfClosed: true,
            openedAtAuthenticationHost: false
        ))
        XCTAssertTrue(WebRoutingPolicy.shouldReloadOpener(
            selfClosed: false,
            openedAtAuthenticationHost: true
        ))

        XCTAssertTrue(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: true,
            landedHost: "workspace.slack.com",
            openerHost: "app.slack.com",
            serviceHost: "app.slack.com"
        ))
        XCTAssertTrue(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: true,
            landedHost: "mail.google.com",
            openerHost: "mail.google.com",
            serviceHost: "mail.google.com"
        ))
        XCTAssertTrue(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: true,
            landedHost: "outlook.cloud.microsoft",
            openerHost: "outlook.cloud.microsoft",
            serviceHost: "outlook.cloud.microsoft"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: true,
            landedHost: "accounts.google.com",
            openerHost: "mail.google.com",
            serviceHost: "mail.google.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: false,
            landedHost: "workspace.slack.com",
            openerHost: "app.slack.com",
            serviceHost: "app.slack.com"
        ))

        XCTAssertTrue(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: true,
            landedHost: "calendar.google.com",
            openerHost: "workspace.google.com",
            serviceHost: "calendar.google.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: true,
            landedHost: "drive.google.com",
            openerHost: "workspace.google.com",
            serviceHost: "calendar.google.com"
        ))

        XCTAssertTrue(WebRoutingPolicy.shouldLoadServiceHomeAfterAuthentication(
            openedAtAuthenticationHost: true,
            openerHost: "workspace.google.com",
            serviceHost: "calendar.google.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldLoadServiceHomeAfterAuthentication(
            openedAtAuthenticationHost: true,
            openerHost: "calendar.google.com",
            serviceHost: "calendar.google.com"
        ))
        XCTAssertFalse(WebRoutingPolicy.shouldLoadServiceHomeAfterAuthentication(
            openedAtAuthenticationHost: false,
            openerHost: "workspace.google.com",
            serviceHost: "calendar.google.com"
        ))
    }

    func testExternalOpenSchemes() {
        for value in [
            "https://example.com/a",
            "http://example.com",
            "HTTPS://example.com",
            "mailto:someone@example.com",
            "tel:+15551234",
            "maps://?q=test",
        ] {
            XCTAssertTrue(WebRoutingPolicy.isSafeForExternalOpen(URL(string: value)!))
        }
        for value in [
            "smb://attacker.example/share",
            "afp://attacker.example/share",
            "ftp://attacker.example/file",
            "vnc://attacker.example",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "ssh://attacker.example",
            "someapp://do-something",
        ] {
            XCTAssertFalse(WebRoutingPolicy.isSafeForExternalOpen(URL(string: value)!))
        }
    }

    func testDownloadFilenameSanitization() {
        let cases: [(String, String)] = [
            ("../../etc/passwd", "passwd"),
            ("report.pdf", "report.pdf"),
            ("a/b/c.txt", "c.txt"),
            ("folder:name.pdf", "folder-name.pdf"),
            ("", "download"),
            ("   ", "download"),
            ("/", "download"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(WebRoutingPolicy.sanitizedDownloadFilename(input), expected)
        }
    }
}
