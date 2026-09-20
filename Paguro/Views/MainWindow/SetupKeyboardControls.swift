import AppKit
import SwiftUI

/// Setup remains keyboard accessible even when macOS limits Tab to text inputs.
struct SetupKeyboardActivation: ViewModifier {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    // Arrow keys can carry numeric-pad and function flags without a held modifier.
    static func accepts(_ modifiers: EventModifiers) -> Bool {
        modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    }

    func body(content: Content) -> some View {
        content
            .focusable(interactions: .edit)
            .onKeyPress(keys: [.space, .return]) { key in
                guard isEnabled, Self.accepts(key.modifiers) else { return .ignored }
                action()
                return .handled
            }
    }
}

/// A native popup keeps menu keyboard handling and opts into the wizard's Tab order.
struct SetupChoiceMenu: NSViewRepresentable {
    let categories: [String]
    var labels: [String: String] = [:]
    var accessibilityName = "Category"
    let keyboardControl: KeyboardControl
    @Binding var selection: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> Popup {
        let popup = Popup(frame: .zero, pullsDown: false)
        popup.isBordered = false
        popup.font = .systemFont(ofSize: PaguroTypeSize.body)
        popup.focusRingType = .exterior
        popup.setAccessibilityLabel(accessibilityName)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectCategory(_:))
        keyboardControl.popup = popup
        return popup
    }

    func updateNSView(_ popup: Popup, context: Context) {
        context.coordinator.selection = $selection
        popup.isEnabled = isEnabled
        popup.setChoices(categories, labels: labels)
        popup.selectItem(at: categories.firstIndex(of: selection) ?? -1)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Popup, context: Context) -> CGSize? {
        // Measure one title so longer, unselected menu items do not widen the control.
        let sizingCell = NSPopUpButtonCell(textCell: nsView.titleOfSelectedItem ?? "", pullsDown: false)
        sizingCell.isBordered = nsView.isBordered
        sizingCell.font = nsView.font
        sizingCell.controlSize = nsView.controlSize
        return sizingCell.cellSize
    }

    @MainActor
    final class KeyboardControl {
        weak var popup: Popup?

        func open() {
            guard let popup, popup.isEnabled else { return }
            popup.performClick(nil)
        }
    }

    final class Popup: NSPopUpButton {
        func setChoices(_ ids: [String], labels: [String: String]) {
            let titles = ids.map { labels[$0] ?? $0 }
            guard itemTitles != titles || itemArray.compactMap({ $0.representedObject as? String }) != ids else { return }
            let choices = NSMenu()
            for (id, title) in zip(ids, titles) {
                // NSPopUpButton.addItems removes duplicate titles, but workspace names can match.
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = id
                choices.addItem(item)
            }
            menu = choices
        }

        override var acceptsFirstResponder: Bool { isEnabled }
        // The SwiftUI wrapper supplies one Tab stop and forwards menu activation.
        override var canBecomeKeyView: Bool { false }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        @objc func selectCategory(_ sender: NSPopUpButton) {
            guard sender.isEnabled, let title = sender.titleOfSelectedItem else { return }
            selection.wrappedValue = sender.selectedItem?.representedObject as? String ?? title
        }
    }
}
