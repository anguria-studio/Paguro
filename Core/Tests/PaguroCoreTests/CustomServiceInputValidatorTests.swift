import Testing
@testable import PaguroCore

struct CustomServiceInputValidatorTests {
    @Test
    func validInputIsTrimmedAndNormalized() {
        #expect(CustomServiceInputValidator.validate(
            label: "  Docs  ",
            url: " HTTPS://example.com/app "
        ) == .valid(label: "Docs", url: "https://example.com/app"))
    }

    @Test
    func invalidInputReturnsASpecificReason() {
        #expect(CustomServiceInputValidator.validate(
            label: "   ",
            url: "https://example.com"
        ) == .invalid("Label can't be empty"))
        #expect(CustomServiceInputValidator.validate(
            label: "Broken",
            url: "https://"
        ) == .invalid("URL must include a host"))
        #expect(CustomServiceInputValidator.validate(
            label: "FTP",
            url: "ftp://example.com"
        ) == .invalid("URL must start with https:// or http://"))
        #expect(CustomServiceInputValidator.validate(
            label: "Missing",
            url: "example.com"
        ) == .invalid("URL must start with https:// or http://"))
    }
}
