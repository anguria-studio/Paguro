import AppKit
import SwiftUI
import XCTest
@testable import Paguro

@MainActor
final class SetupCategoryMenuTests: XCTestCase {
    func testWrapperOwnsTheOnlyTabStopButNativeMenuCanReceiveFocus() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let menu = SetupCategoryMenu.Popup(frame: NSRect(x: 10, y: 10, width: 170, height: 36), pullsDown: false)
        window.contentView?.addSubview(menu)
        XCTAssertFalse(menu.canBecomeKeyView)
        XCTAssertTrue(window.makeFirstResponder(menu))
        menu.isEnabled = false
        XCTAssertFalse(menu.acceptsFirstResponder)
        XCTAssertFalse(menu.canBecomeKeyView)
        withExtendedLifetime(window) {}
    }

    func testNavigationAcceptsArrowKeyFlags() {
        XCTAssertTrue(SetupKeyboardActivation.accepts([]))
        XCTAssertTrue(SetupKeyboardActivation.accepts([.numericPad, .function]))
        XCTAssertTrue(SetupKeyboardActivation.accepts(.capsLock))
    }

    func testNavigationLeavesModifiedShortcutsAlone() {
        for modifier: EventModifiers in [.command, .option, .control, .shift] {
            XCTAssertFalse(SetupKeyboardActivation.accepts(modifier))
            XCTAssertFalse(SetupKeyboardActivation.accepts([modifier, .numericPad]))
        }
    }

    func testMenuSelectionUpdatesBindingAndRejectsDisabledAction() {
        var category = "All services"
        let coordinator = SetupCategoryMenu.Coordinator(selection: Binding(get: { category }, set: { category = $0 }))
        let menu = SetupCategoryMenu.Popup(frame: .zero, pullsDown: false)
        menu.addItems(withTitles: ["All services", "AI", "Custom websites"])
        menu.selectItem(withTitle: "AI")
        coordinator.selectCategory(menu)
        XCTAssertEqual(category, "AI")
        menu.isEnabled = false
        menu.selectItem(withTitle: "Custom websites")
        coordinator.selectCategory(menu)
        XCTAssertEqual(category, "AI")
    }
}
