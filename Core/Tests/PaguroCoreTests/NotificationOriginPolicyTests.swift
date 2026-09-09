import Testing
@testable import PaguroCore

struct NotificationOriginPolicyTests {
    @Test
    func originTable() {
        let httpsMain = NotificationOrigin(
            scheme: "https",
            host: "app.example.com",
            port: nil
        )
        let cases: [(
            name: String,
            isMainFrame: Bool,
            main: NotificationOrigin?,
            frame: NotificationOrigin?,
            expected: Bool
        )] = [
            ("main frame", true, nil, nil, true),
            ("same origin", false, httpsMain,
             NotificationOrigin(scheme: "https", host: "app.example.com", port: 0), true),
            ("explicit default port", false, httpsMain,
             NotificationOrigin(scheme: "HTTPS", host: "APP.EXAMPLE.COM", port: 443), true),
            ("different scheme", false, httpsMain,
             NotificationOrigin(scheme: "http", host: "app.example.com", port: 0), false),
            ("different host", false, httpsMain,
             NotificationOrigin(scheme: "https", host: "evil.example.com", port: 0), false),
            ("different port", false, httpsMain,
             NotificationOrigin(scheme: "https", host: "app.example.com", port: 8443), false),
            ("missing main origin", false, nil,
             NotificationOrigin(scheme: "https", host: "app.example.com", port: 443), false),
            ("missing frame host", false, httpsMain,
             NotificationOrigin(scheme: "https", host: "", port: 443), false),
            ("non-web origin", false,
             NotificationOrigin(scheme: "file", host: "app.example.com", port: nil),
             NotificationOrigin(scheme: "file", host: "app.example.com", port: nil), false),
        ]

        for item in cases {
            #expect(NotificationOriginPolicy.accepts(
                isMainFrame: item.isMainFrame,
                mainOrigin: item.main,
                frameOrigin: item.frame
            ) == item.expected, Comment(rawValue: item.name))
        }
    }
}
