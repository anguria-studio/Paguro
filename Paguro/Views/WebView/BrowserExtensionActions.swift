#if !APP_STORE
import AppKit
import SwiftUI
import WebKit

@available(macOS 15.4, *)
struct BrowserExtensionActions: View {
    let manager: BrowserExtensionManager
    let serviceID: UUID
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var presenter = BrowserExtensionMenuPresenter()

    var body: some View {
        let entries = Self.menuEntries(manager: manager, serviceID: serviceID)
        let hasUpdates = entries.contains { $0.updateVersion != nil }
        let hasDiagnostics = entries.contains(where: \.hasDiagnostics)
        if !entries.isEmpty {
            Button {
                presenter.show(entries, openOptions: { id, anchor in
                    manager.openOptions(id, for: serviceID, from: anchor)
                }, showDiagnostics: { id, anchor in
                    manager.showDiagnostics(id, for: serviceID, from: anchor)
                }, reviewUpdate: { id in
                    openSettings()
                    manager.reviewUpdate(id)
                }) { id, anchor in
                    manager.performAction(id, for: serviceID, from: anchor)
                }
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .overlay(alignment: .topTrailing) {
                        // Blue for an update wins over orange for diagnostics.
                        if hasUpdates || hasDiagnostics {
                            Circle().fill(hasUpdates ? .blue : .orange).frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(PaguroToolbarButtonStyle())
            .toolbarControlSurface(
                intensity: appState.liquidGlassIntensity, glassStyle: appState.liquidGlassStyle
            )
            .background {
                ExtensionMenuAnchor(presenter: presenter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .help("Extensions for this service")
            .accessibilityLabel("Extensions"
                + (hasUpdates ? ", updates available" : "")
                + (hasDiagnostics ? ", runtime diagnostics available" : ""))
            .accessibilityIdentifier("web.extensions")
            .onDisappear { presenter.cancel() }
        }
    }

    static func menuEntries(manager: BrowserExtensionManager, serviceID: UUID) -> [BrowserExtensionMenuEntry] {
        let actions = Dictionary(uniqueKeysWithValues: manager.actions(for: serviceID).map { ($0.id, $0.action) })
        let updates = manager.availableUpdates
        return manager.records.filter { $0.serviceIDs.contains(serviceID) }.map { record in
            let action = actions[record.id]
            return BrowserExtensionMenuEntry(
                id: record.id, name: record.name,
                image: action?.icon(for: CGSize(width: 16, height: 16)),
                isEnabled: action?.isEnabled == true,
                help: action?.label ?? "This extension has no available action.",
                hasOptions: manager.hasOptions(record.id, for: serviceID),
                hasDiagnostics: manager.runtimeIssues[serviceID]?[record.id]?.isEmpty == false,
                updateVersion: updates[record.id]?.version
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct BrowserExtensionMenuEntry {
    let id: UUID
    let name: String
    var image: NSImage?
    var isEnabled = true
    var help: String?
    var hasOptions = false
    var hasDiagnostics = false
    var updateVersion: String?
}

/// End native menu tracking before asking WebKit to present an action popup.
@MainActor
final class BrowserExtensionMenuPresenter: NSObject {
    /// What the user picked. It runs only after the menu closes.
    private enum Choice {
        case perform(UUID), options(UUID), diagnostics(UUID), update(UUID)
    }

    /// `NSMenuItem.representedObject` needs an object.
    private final class ChoiceBox: NSObject {
        let choice: Choice
        init(_ choice: Choice) { self.choice = choice }
    }

    weak var anchor: NSView?
    private var activeMenu: NSMenu?
    private var selection: Choice?
    private let trackMenu: (NSMenu, NSView) -> Void

    init(trackMenu: @escaping (NSMenu, NSView) -> Void = { menu, anchor in
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.minX, y: anchor.bounds.minY), in: anchor)
    }) {
        self.trackMenu = trackMenu
    }

    func show(_ entries: [BrowserExtensionMenuEntry], openOptions: (UUID, NSView) -> Void = { _, _ in },
              showDiagnostics: (UUID, NSView) -> Void = { _, _ in },
              reviewUpdate: (UUID) -> Void = { _ in },
              perform: (UUID, NSView) -> Void) {
        guard activeMenu == nil, !entries.isEmpty, let anchor, anchor.window != nil else { return }
        let menu = NSMenu(title: "Extensions")
        menu.autoenablesItems = false
        for entry in entries { menu.addItem(makeEntryItem(entry)) }

        activeMenu = menu
        selection = nil
        trackMenu(menu, anchor)
        activeMenu = nil
        let choice = selection
        selection = nil
        guard anchor.window != nil, let choice else { return }
        switch choice {
        case .update(let id): reviewUpdate(id)
        case .diagnostics(let id): showDiagnostics(id, anchor)
        case .options(let id): openOptions(id, anchor)
        case .perform(let id): perform(id, anchor)
        }
    }

    func cancel() {
        selection = nil
        activeMenu?.cancelTracking()
    }

    private func makeEntryItem(_ entry: BrowserExtensionMenuEntry) -> NSMenuItem {
        let item = makeItem(entry.name, .perform(entry.id), isEnabled: entry.isEnabled)
        item.toolTip = entry.help
        item.image = entry.image?.copy() as? NSImage
        item.image?.size = NSSize(width: 16, height: 16)
        guard entry.hasOptions || entry.hasDiagnostics || entry.updateVersion != nil else { return item }

        // The submenu keeps Diagnostics and Review update reachable when the action is unavailable.
        let submenu = NSMenu(title: entry.name)
        submenu.autoenablesItems = false
        submenu.addItem(makeItem("Open extension", .perform(entry.id), isEnabled: entry.isEnabled))
        if entry.hasOptions {
            submenu.addItem(makeItem("Settings…", .options(entry.id)))
        }
        if entry.hasDiagnostics {
            submenu.addItem(makeItem("Diagnostics…", .diagnostics(entry.id), symbol: "exclamationmark.circle"))
        }
        if let version = entry.updateVersion {
            let update = makeItem("Review update to \(version)…", .update(entry.id), symbol: "arrow.down.circle")
            update.toolTip = "Opens the update review in Paguro Settings > Extensions."
            submenu.addItem(update)
        }
        item.submenu = submenu
        item.isEnabled = true
        return item
    }

    private func makeItem(_ title: String, _ choice: Choice, isEnabled: Bool = true, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(select(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ChoiceBox(choice)
        item.isEnabled = isEnabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    @objc private func select(_ item: NSMenuItem) {
        // Ignore late actions from a menu that is no longer the one being tracked.
        guard item.isEnabled, let activeMenu,
              item.menu === activeMenu || item.menu?.supermenu === activeMenu,
              let box = item.representedObject as? ChoiceBox else { return }
        selection = box.choice
    }
}

private struct ExtensionMenuAnchor: NSViewRepresentable {
    let presenter: BrowserExtensionMenuPresenter

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        presenter.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { presenter.anchor = view }
}
#endif
