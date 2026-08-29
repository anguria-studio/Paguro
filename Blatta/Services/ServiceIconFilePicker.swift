import AppKit
import UniformTypeIdentifiers

/// Opens the native image picker and returns validated icon bytes.
@MainActor
enum ServiceIconFilePicker {
    static func pickImageData(
        message: String = "Choose a service icon"
    ) throws -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try ServiceIconImageProcessor.normalizedPNG(from: data)
    }
}
