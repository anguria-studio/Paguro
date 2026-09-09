import Foundation
import Testing
@testable import PaguroCore

struct ConfigurationArchiveTests {
    private func fixture() -> ConfigurationArchive {
        var service = ConfigurationService()
        service.label = "Mail"
        service.url = "https://example.com/inbox"
        service.customCSS = "body { color: red; }\n"
        var workspace = ConfigurationWorkspace()
        workspace.name = "Personal"
        workspace.serviceIDs = [service.id]
        var archive = ConfigurationArchive()
        archive.services = [service]
        archive.workspaces = [workspace]
        return archive
    }

    @Test func roundTripPreservesConfiguration() throws {
        let archive = fixture()
        #expect(try ConfigurationArchiveCodec.decode(ConfigurationArchiveCodec.encode(archive)) == archive)
    }

    @Test func unsupportedVersionIsRejected() {
        var archive = fixture()
        archive.version = 2
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
    }

    @Test func duplicateAndMissingReferencesAreRejected() {
        var archive = fixture()
        archive.services.append(archive.services[0])
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
        archive = fixture()
        archive.workspaces[0].serviceIDs.append(UUID())
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
        archive = fixture()
        archive.workspaces[0].serviceIDs.append(archive.services[0].id)
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "https://user:secret@example.com", "https://", "https://example.com\n"])
    func invalidURLsAreRejected(_ url: String) {
        var archive = fixture()
        archive.services[0].url = url
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
    }

    @Test func invalidSettingsAreRejected() {
        var archive = fixture()
        archive.preferences.defaultZoom = .infinity
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
        archive = fixture()
        archive.preferences.dndStartMinutes = 1440
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
        archive = fixture()
        archive.services[0].cameraPolicy = "unknown"
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
    }

    @Test func oversizedInputsAreRejected() {
        #expect(throws: ConfigurationArchiveError.self) {
            try ConfigurationArchiveCodec.decode(Data(repeating: 32, count: ConfigurationArchiveCodec.maximumBytes + 1))
        }
        var archive = fixture()
        archive.services[0].customIconData = Data(repeating: 0, count: 1_048_577)
        #expect(throws: ConfigurationArchiveError.self) { try ConfigurationArchiveCodec.validate(archive) }
    }

    @Test func truncatedFileIsRejected() {
        #expect(throws: ConfigurationArchiveError.self) {
            try ConfigurationArchiveCodec.decode(Data("{\"version\":1}".utf8))
        }
    }

    @Test func exportHasNoBrowserSessionFields() throws {
        let text = String(decoding: try ConfigurationArchiveCodec.encode(fixture()), as: UTF8.self)
        for field in ["dataStoreIdentifier", "cookies", "password", "fetchedIconData", "lastAccessedAt", "selectedServiceID"] {
            #expect(!text.contains("\"\(field)\""))
        }
    }
}
