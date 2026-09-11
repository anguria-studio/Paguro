import SwiftUI
import PaguroCore

/// Lists every store Paguro could put back: the live one and each backup it
/// kept. The user picks; nothing is written until they do.
struct StoreRecoveryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// The selected candidate's `id` (its `url.path`), not the candidate
    /// itself. `List(_:selection:)` ties selection directly to
    /// `Data.Element.ID` only when the selection type IS that ID type;
    /// binding to `StoreCandidate` itself instead compiles (it's `Hashable`)
    /// but falls back to matching against each row's `.tag(_:)`, a second,
    /// independent identity path that could silently stop tracking selection
    /// with no test able to see it. Keying on the id sidesteps that risk
    /// entirely rather than relying on `.tag` being honored.
    @State private var selectionID: StoreCandidate.ID?

    /// Shown when the restore cannot start. Keep the sheet open because the
    /// user still needs an accurate result and a manual restart instruction.
    @State private var failureMessage: String?

    private var selectedCandidate: StoreCandidate? {
        appState.storeRecovery.candidates.first { $0.id == selectionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore your workspaces and services")
                .font(.headline)
            Text("Paguro keeps a copy of your data before each update. Pick the one you want and Paguro will restart to put it back. Your current data is set aside first, so nothing is thrown away.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(appState.storeRecovery.candidates, selection: $selectionID) { candidate in
                row(for: candidate)
            }
            .frame(minHeight: 200)

            if let failureMessage {
                Text(failureMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let folder = appState.storeRecovery.candidates.first?.url.deletingLastPathComponent() {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore and Restart") {
                    guard let selectedCandidate else { return }
                    guard appState.storeRecovery.chooseRestore(selectedCandidate) else {
                        failureMessage = "Paguro could not restart itself. Quit and open it again to put this backup back."
                        return
                    }
                    // Closing this sheet is what lets the quit through: AppKit
                    // will not terminate while a sheet is attached. The restart
                    // itself runs from the sheet's `onDismiss`.
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCandidate?.isRestorable != true)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            appState.storeRecovery.refreshCandidates()
            selectionID = appState.storeRecovery.preselectedCandidate?.id
        }
    }

    @ViewBuilder
    private func row(for candidate: StoreCandidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(candidate.displayTitle).fontWeight(.medium)
                if candidate.kind == .live {
                    Text("Current")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
            }
            Text(candidate.displayDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
