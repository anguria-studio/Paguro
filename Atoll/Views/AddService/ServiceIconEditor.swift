import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AtollCore

/// Edits the icon bytes that are saved with one service.
///
/// A fetched website icon is stored as a custom icon so it keeps precedence over
/// a bundled catalog mark. The source URL is only used for the fetch; Atoll
/// stores the resulting image, not a permanent remote dependency.
struct ServiceIconEditor: View {
    let label: String
    let serviceURL: String
    var fallbackIconData: Data?
    var fallbackCatalogID: String?
    @Binding var customIconData: Data?
    @Binding var websiteURL: String

    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                preview

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Choose Image…") {
                            chooseImage()
                        }

                        if customIconData != nil {
                            Button("Use Default") {
                                customIconData = nil
                                errorMessage = nil
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(
                            "Website or image URL",
                            text: $websiteURL,
                            prompt: Text("Uses the service address")
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Icon website or image address")
                        .onChange(of: websiteURL) {
                            errorMessage = nil
                        }

                        Button {
                            fetchWebsiteIcon()
                        } label: {
                            if isFetching {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Fetch")
                            }
                        }
                        .disabled(isFetching || fetchSourceIsEmpty)
                        .accessibilityLabel("Fetch service icon")
                    }

                    Text("Leave the field blank to discover the icon from the service address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Icon error: \(errorMessage)")
                    }
                }
            }
        }
        .onDisappear {
            fetchTask?.cancel()
        }
    }

    private var fetchSourceIsEmpty: Bool {
        websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && serviceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let data = customIconData,
               let image = ServiceIconImageProcessor.displayImage(from: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let assetName = fallbackAssetName {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            } else if let data = fallbackIconData,
                      let image = ServiceIconImageProcessor.displayImage(from: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text(ServiceIconPalette.initial(for: label))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ServiceIconPalette.color(for: label))
            }
        }
        .frame(width: 64, height: 64)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AtollRadius.icon))
        .overlay {
            RoundedRectangle(cornerRadius: AtollRadius.icon)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Icon preview for \(label)")
    }

    private var fallbackAssetName: String? {
        guard let fallbackCatalogID else { return nil }
        let name = "brand-\(fallbackCatalogID)"
        return NSImage(named: name) == nil ? nil : name
    }

    private func chooseImage() {
        fetchTask?.cancel()
        isFetching = false

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an icon for \(label)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            customIconData = try ServiceIconImageProcessor.normalizedPNG(from: data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchWebsiteIcon() {
        guard let sourceURL = ServiceIconSource.normalizedURL(
            from: websiteURL,
            fallbackURL: serviceURL
        ) else {
            errorMessage = "Enter a valid HTTP or HTTPS website address."
            return
        }

        fetchTask?.cancel()
        isFetching = true
        errorMessage = nil
        fetchTask = Task {
            let data = await FaviconFetcher.shared.fetchFavicon(for: sourceURL.absoluteString)
            guard !Task.isCancelled else { return }
            isFetching = false

            guard let data else {
                errorMessage = "No usable icon was found at that address."
                return
            }

            do {
                customIconData = try ServiceIconImageProcessor.normalizedPNG(from: data)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
