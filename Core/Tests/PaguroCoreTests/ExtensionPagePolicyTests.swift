import Foundation
import Testing
@testable import PaguroCore

struct ExtensionPagePolicyTests {
    private let base = URL(string: "webkit-extension://account-extension/")!

    @Test func acceptsWebPagesAndOnlyItsOwnExtensionResources() {
        for value in ["https://translate.google.com/?u=https%3A%2F%2Fexample.com", "http://127.0.0.1/test",
                      "webkit-extension://account-extension/options.html", "WEBKIT-EXTENSION://account-extension/options.html", "about:blank"] {
            #expect(ExtensionPagePolicy.allows(URL(string: value)!, extensionBaseURL: base))
        }
    }

    @Test func rejectsUnsafeSchemesCredentialsOtherExtensionsAndOversizeInput() {
        for value in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,test",
                      "https://user:password@example.com/", "webkit-extension://another/options.html",
                      "webkit-extension://account-extension:123/options.html", "about:config",
                      "https://example.com/" + String(repeating: "a", count: 16_384)] {
            #expect(!ExtensionPagePolicy.allows(URL(string: value)!, extensionBaseURL: base))
        }
    }

    @Test func subframesAcceptLocalDocumentsButNotScriptsOrFiles() {
        for value in ["blob:webkit-extension://account-extension/1234", "data:text/html,test", "about:srcdoc",
                      "https://example.com/frame", "webkit-extension://account-extension/frame.html"] {
            #expect(ExtensionPagePolicy.allowsSubframe(URL(string: value)!, extensionBaseURL: base))
        }
        for value in ["javascript:alert(1)", "file:///etc/passwd", "about:config",
                      "webkit-extension://another/frame.html", "https://user:password@example.com/"] {
            #expect(!ExtensionPagePolicy.allowsSubframe(URL(string: value)!, extensionBaseURL: base))
        }
    }
}

struct PackageDigestTests {
    @Test func acceptsOnlyLowercaseSixtyFourCharacterHex() {
        #expect(PackageDigest.isValidSHA256(String(repeating: "a1", count: 32)))
        #expect(!PackageDigest.isValidSHA256(String(repeating: "A1", count: 32)))
        #expect(!PackageDigest.isValidSHA256(String(repeating: "a", count: 63)))
        #expect(!PackageDigest.isValidSHA256(String(repeating: "g", count: 64)))
    }
}
