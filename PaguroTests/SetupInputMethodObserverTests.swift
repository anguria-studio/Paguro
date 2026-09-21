import AppKit
import XCTest
@testable import Paguro

@MainActor
final class SetupInputMethodObserverTests: XCTestCase {
    func testMouseDownHidesOutlineBeforeButtonActivationAndTabRestoresIt() throws {
        let window = makeWindow()
        let view = SetupInputMethodObserver.InputView()
        window.contentView?.addSubview(view)
        defer { view.removeFromSuperview() }
        view.isEnabled = true
        var keyboardFocus = true
        view.onChange = { keyboardFocus = $0 }

        view.observe(try mouseDown(in: window))
        XCTAssertFalse(keyboardFocus, "The outline must be hidden before mouse-up activates a card.")

        view.observe(try keyDown(in: window, modifiers: .shift))
        XCTAssertTrue(keyboardFocus, "Shift-Tab must restore keyboard feedback too.")
    }

    func testHiddenCatalogAndOtherWindowsDoNotChangeInputMode() throws {
        let window = makeWindow()
        let otherWindow = makeWindow()
        let view = SetupInputMethodObserver.InputView()
        window.contentView?.addSubview(view)
        defer { view.removeFromSuperview() }
        var changes = 0
        view.onChange = { _ in changes += 1 }

        view.observe(try mouseDown(in: window))
        view.isEnabled = true
        view.observe(try mouseDown(in: otherWindow))
        view.observe(try keyDown(in: window, modifiers: .command))
        XCTAssertEqual(changes, 0)

        view.observe(try keyDown(in: window))
        XCTAssertEqual(changes, 1)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func mouseDown(in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func keyDown(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                     timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                     characters: "\t", charactersIgnoringModifiers: "\t",
                                     isARepeat: false, keyCode: 48))
    }
}
