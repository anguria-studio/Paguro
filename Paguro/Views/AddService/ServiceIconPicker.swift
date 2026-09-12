import AppKit
import SwiftUI

/// Compact automatic icon preview. Detailed URL overrides remain in Edit service.
struct ServiceIconPicker: View {
    let label: String
    let draft: ServiceIconDraft

    var body: some View {
        VStack(spacing: 8) {
            preview
                .frame(width: 64, height: 64)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: PaguroRadius.icon))
                .overlay {
                    RoundedRectangle(cornerRadius: PaguroRadius.icon)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .overlay(alignment: .bottomTrailing) {
                    if draft.isFetching {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(4)
                            .background(.regularMaterial, in: Circle())
                            .accessibilityLabel("Finding website icon")
                    }
                }
                .accessibilityLabel("Icon preview for \(label)")

            Menu("Change Icon…") {
                Button("Choose Image…") { chooseImage() }
                Button("Use Website Icon") { draft.useWebsiteIcon() }
            }
            .fixedSize()
            .accessibilityLabel("Change service icon")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let data = draft.customIconData ?? draft.fetchedIconData,
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

    private func chooseImage() {
        do {
            guard let data = try ServiceIconFilePicker.pickImageData(
                message: "Choose an icon for \(label)"
            ) else { return }
            draft.chooseImage(data)
        } catch {
            draft.showError(error)
        }
    }
}
