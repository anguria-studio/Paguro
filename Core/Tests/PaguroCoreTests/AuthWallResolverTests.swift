import Testing
@testable import PaguroCore

struct AuthWallResolverTests {
    @Test
    func offHostFetchWithoutABadgeLooksLikeASignInWall() {
        #expect(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: "login.microsoftonline.com",
            badge: 0
        ))
    }

    @Test
    func healthyAndUnknownFetchesDoNotLookLikeSignInWalls() {
        #expect(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: "outlook.cloud.microsoft",
            badge: 0
        ) == false)
        #expect(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: "outlook.office.com",
            badge: 3
        ) == false)
        #expect(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "outlook.cloud.microsoft",
            landedHost: nil,
            badge: 0
        ) == false)
        #expect(AuthWallResolver.looksLikeSignInWall(
            requestedHost: nil,
            landedHost: "login.microsoftonline.com",
            badge: 0
        ) == false)
    }

    @Test
    func hostnameComparisonIsCaseInsensitive() {
        #expect(AuthWallResolver.looksLikeSignInWall(
            requestedHost: "OUTLOOK.cloud.microsoft",
            landedHost: "outlook.CLOUD.microsoft",
            badge: 0
        ) == false)
    }
}
