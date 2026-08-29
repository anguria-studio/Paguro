import SwiftUI

struct CatalogGridView: View {
    let searchText: String
    let spaceID: UUID
    let onAdd: () -> Void

    @Environment(AppState.self) private var appState

    private let catalog = ServiceCatalog.shared
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)
    ]

    private var filteredEntries: [ServiceCatalogEntry] {
        if searchText.isEmpty { return catalog.entries }
        let query = searchText.lowercased()
        return catalog.entries.filter {
            $0.name.lowercased().contains(query) ||
            $0.category.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    private var groupedEntries: [(String, [ServiceCatalogEntry])] {
        let grouped = Dictionary(grouping: filteredEntries, by: \.category)
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groupedEntries, id: \.0) { category, entries in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(entries) { entry in
                                CatalogEntryButton(entry: entry) {
                                    addService(from: entry)
                                }
                            }
                        }
                    }
                }

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term or add a custom URL")
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func addService(from entry: ServiceCatalogEntry) {
        guard appState.addService(
            label: entry.name,
            url: entry.url,
            catalogEntryID: entry.id,
            userAgent: entry.userAgent,
            to: spaceID
        ) != nil else { return }

        onAdd()
    }
}

private struct CatalogEntryButton: View {
    let entry: ServiceCatalogEntry
    let action: () -> Void

    @State private var isHovering = false
    @State private var icon: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                iconView
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: BlattaRadius.control))

                Text(entry.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BlattaRadius.control)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(entry.description)
        .accessibilityLabel("Add \(entry.name)")
        .task {
            icon = await CatalogIconCache.shared.icon(for: entry.id)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Text(String(entry.name.prefix(1)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: BlattaRadius.control)
                        .fill(colorForCategory(entry.category))
                )
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category.lowercased() {
        case "email": return .blue
        case "messaging": return .purple
        case "social": return .pink
        case "productivity": return .green
        case "ai": return .orange
        default: return .gray
        }
    }
}
