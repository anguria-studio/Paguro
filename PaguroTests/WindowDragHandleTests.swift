import AppKit
import XCTest
@testable import Paguro

@MainActor
final class WindowDragHandleTests: XCTestCase {
    func testOnboardingBackgroundEndsTextEditing() throws {
        let (window, field, handle) = makeWindow()
        handle.endsEditingOnPress = true
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertNotNil(field.currentEditor())
        handle.endEditingIfNeeded()
        XCTAssertNil(field.currentEditor())
        withExtendedLifetime(window) {}
    }

    func testOtherDragSurfacesKeepTextEditing() throws {
        let (window, field, handle) = makeWindow()
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        handle.endEditingIfNeeded()
        XCTAssertTrue(window.firstResponder === editor)
        withExtendedLifetime(window) {}
    }

    private func makeWindow() -> (NSWindow, NSTextField, WindowDragHandle.DragView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 20, y: 100, width: 200, height: 24))
        field.stringValue = "Personal"
        let handle = WindowDragHandle.DragView(frame: NSRect(x: 0, y: 0, width: 400, height: 50))
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(handle)
        return (window, field, handle)
    }
}
