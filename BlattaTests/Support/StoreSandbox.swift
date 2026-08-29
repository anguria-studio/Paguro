import Foundation
import XCTest

struct StoreSandbox {
    let directoryURL: URL
    let storeURL: URL
    let defaults: UserDefaults

    init(testCase: XCTestCase, label: String, storeName: String = "store.sqlite") throws {
        let identifier = UUID().uuidString
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blatta-\(label)-\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let suiteName = "BlattaTests.\(label).\(identifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }

        self.directoryURL = directoryURL
        self.storeURL = directoryURL.appendingPathComponent(storeName)
        self.defaults = defaults

        testCase.addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    static func relocationDirectories(
        label: String
    ) throws -> (support: URL, legacy: URL, scoped: URL) {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("blatta-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (
            support,
            support.appendingPathComponent("default.store"),
            support.appendingPathComponent("Blatta").appendingPathComponent("default.store")
        )
    }
}
