import Foundation
import Testing
@testable import PaguroCore

/// New-window requests that leave the service use the outside-link route.
/// Sign-in popups and child popups stay in Paguro.
struct NewWindowRoutingTests {
    private func routes(
        _ target: String?,
        from opener: String? = "app.slack.com",
        openerIsPopup: Bool = false,
        sized: Bool = false
    ) -> Bool {
        WebRoutingPolicy.shouldRouteNewWindowExternally(
            targetURL: target.flatMap(URL.init(string:)),
            openerHost: opener,
            openerIsPopup: openerIsPopup,
            requestsWindowSize: sized
        )
    }

    @Test("A cross-service link from a service uses the outside-link route")
    func crossServiceLinkRoutesExternally() {
        #expect(routes("https://linear.app/team/issue/ABC-1"))
        #expect(routes("http://example.com/page"))
        #expect(routes("https://docs.google.com/document/d/1", from: "mail.google.com"))
    }

    @Test("A same-service new window stays in Paguro")
    func sameServiceStays() {
        #expect(!routes("https://myteam.slack.com/archives/C1"))
        #expect(!routes("https://files.slack.com/files-pri/T1/F1"))
    }

    @Test("A known sign-in host stays in a popup")
    func authenticationHostStays() {
        #expect(!routes("https://accounts.google.com/o/oauth2/v2/auth"))
        #expect(!routes("https://login.microsoftonline.com/common/oauth2", from: "teams.cloud.microsoft"))
        #expect(!routes("https://appleid.apple.com/auth/authorize"))
    }

    @Test("A sized window stays in a popup because it is a probable sign-in flow")
    func sizedWindowStays() {
        #expect(!routes("https://github.com/login/oauth/authorize", sized: true))
        #expect(!routes("https://company.okta.com/oauth2/v1/authorize", sized: true))
    }

    @Test("A request from a popup keeps the child popup")
    func childPopupStays() {
        #expect(!routes("https://linear.app/issue", openerIsPopup: true))
    }

    @Test("Missing or non-web targets and unknown openers keep the popup path")
    func unsafeInputStays() {
        #expect(!routes(nil))
        #expect(!routes("about:blank"))
        #expect(!routes("mailto:someone@example.com"))
        #expect(!routes("data:text/html,hi"))
        #expect(!routes("https://linear.app/issue", from: nil))
        #expect(!routes("https://linear.app/issue", from: ""))
    }
}
