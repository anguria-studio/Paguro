import AppKit
import UniformTypeIdentifiers
import BlattaCore

/// Native file panels provide sandbox access to one user-selected JSON file.
@MainActor
enum ConfigurationFileAccess {
    static func export(_ data: Data) throws -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Blatta Configuration.json"
        panel.title = "Export Configuration"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
        return true
    }

    static func chooseImport() throws -> ConfigurationArchive? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Configuration"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ConfigurationArchiveError.invalid("Choose a regular JSON file.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bound the read even when the file changes after the panel closes.
        let data = try handle.read(upToCount: ConfigurationArchiveCodec.maximumBytes + 1) ?? Data()
        return try ConfigurationArchiveCodec.decode(data)
    }
}
