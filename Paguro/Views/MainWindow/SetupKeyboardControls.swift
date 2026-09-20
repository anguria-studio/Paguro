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
    var action: MenuAction? = nil
    let keyboardControl: KeyboardControl
    @Binding var selection: String
    @Environment(\.isEnabled) private var isEnabled

    struct MenuAction {
        let title: String
        let perform: () -> Void
    }

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
        context.coordinator.action = action?.perform
        popup.isEnabled = isEnabled
        popup.setChoices(categories, labels: labels, actionTitle: action?.title)
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
        static let actionItemTag = 1

        func setChoices(_ ids: [String], labels: [String: String], actionTitle: String? = nil) {
            let titles = ids.map { labels[$0] ?? $0 }
            let items = itemArray.filter { !$0.isSeparatorItem && $0.tag != Self.actionItemTag }
            let currentActionTitle = itemArray.first { $0.tag == Self.actionItemTag }?.title
            guard items.map(\.title) != titles
                || items.compactMap({ $0.representedObject as? String }) != ids
                || currentActionTitle != actionTitle else { return }
            let choices = NSMenu()
            for (id, title) in zip(ids, titles) {
                // NSPopUpButton.addItems removes duplicate titles, but workspace names can match.
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = id
                choices.addItem(item)
            }
            if let actionTitle {
                if !ids.isEmpty { choices.addItem(.separator()) }
                let item = NSMenuItem(title: actionTitle, action: nil, keyEquivalent: "")
                item.tag = Self.actionItemTag
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
        var action: (() -> Void)?
        init(selection: Binding<String>) { self.selection = selection }

        @objc func selectCategory(_ sender: NSPopUpButton) {
            guard sender.isEnabled, let title = sender.titleOfSelectedItem else { return }
            if sender.selectedItem?.tag == Popup.actionItemTag {
                // An action opens an editor; it must not replace the selected workspace.
                sender.selectItem(at: sender.itemArray.firstIndex {
                    $0.representedObject as? String == selection.wrappedValue
                } ?? -1)
                action?()
                return
            }
            selection.wrappedValue = sender.selectedItem?.representedObject as? String ?? title
        }
    }
}
