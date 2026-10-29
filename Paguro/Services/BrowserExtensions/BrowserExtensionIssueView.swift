#if !APP_STORE
import SwiftUI

struct BrowserExtensionIssueView: View {
    let name: String
    let summary: String
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.headline)
            Text(summary).font(.paguroCaption).foregroundStyle(.secondary)
            if messages.isEmpty {
                Text("No runtime diagnostics in this session.").font(.paguroCaption)
            } else {
                BrowserExtensionDiagnosticDetails(messages: messages)
            }
        }
        .padding(16)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct BrowserExtensionDiagnosticDetails: View {
    let messages: [String]

    var body: some View {
        DisclosureGroup {
            ScrollView {
                Text(messages.joined(separator: "\n\n"))
                    .font(.paguroCaption).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        } label: {
            Label("Runtime diagnostics", systemImage: "exclamationmark.circle")
                .font(.paguroCaption)
        }
    }
}
#endif
