#if !APP_STORE
import AppKit
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionPopupLayoutTests: XCTestCase {
    func testCancelledPresentationDoesNotShowAPopup() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }
        let popover = NSPopover()
        popover.contentViewController = NSViewController()
        defer { popover.close() }
        do {
            try await BrowserExtensionPopupContentController.present(popover, relativeTo: NSRect(x: 10, y: 10, width: 20, height: 20),
                of: try XCTUnwrap(window.contentView), preferredEdge: .minY, mayPresent: { false })
            XCTFail("A cancelled presentation must not open")
        } catch is CancellationError { }
        XCTAssertFalse(popover.isShown)
    }

    func testPopupOwnsKeyboardFocusAndTypesIntoItsWebInput() async throws {
        try await PopupFocus.requireActiveApp()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let outside = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        outside.string = "Outside input"
        window.contentView = outside
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(outside)
        defer { window.close() }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        webView.loadHTMLString("<!doctype html><title>Focus fixture</title><input id='focus-input'>", baseURL: nil)
        defer { webView.stopLoading() }
        for _ in 0..<100 {
            if webView.title == "Focus fixture", !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let content = NSViewController()
        content.view = webView
        content.preferredContentSize = NSSize(width: 320, height: 240)
        let popover = NSPopover()
        popover.contentViewController = content
        defer { popover.close() }
        try await BrowserExtensionPopupContentController.present(popover, relativeTo: NSRect(x: 10, y: 50, width: 30, height: 30), of: outside, preferredEdge: .minY)
        for _ in 0..<50 {
            if webView.window?.isKeyWindow == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let popupWindow = try XCTUnwrap(webView.window)
        XCTAssertTrue(popupWindow.isKeyWindow)
        let responder = try XCTUnwrap(popupWindow.firstResponder as? NSView)
        XCTAssertTrue(responder === webView || responder.isDescendant(of: webView))
        _ = try await webView.evaluateJavaScript("document.getElementById('focus-input').focus(); true;")
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: popupWindow.windowNumber, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
        popupWindow.sendEvent(event)
        try await Task.sleep(for: .milliseconds(100))
        let typed = try await webView.evaluateJavaScript("document.getElementById('focus-input').value") as? String
        // The active keyboard layout determines the character for this key code.
        XCTAssertEqual(typed?.count, 1)
        XCTAssertEqual(outside.string, "Outside input")
    }

    func testKeepOpenPreservesTheWebInputAcrossPageFocusAndResetsOnReopening() async throws {
        try await PopupFocus.requireActiveApp()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let outside = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 700))
        outside.string = "Page text to copy"
        window.contentView = outside
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        webView.loadHTMLString("<!doctype html><title>Keep open fixture</title><input id='draft' value='unfinished entry'>", baseURL: nil)
        defer { webView.stopLoading() }
        for _ in 0..<150 {
            if webView.title == "Keep open fixture", !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let content = NSViewController()
        content.view = webView
        content.preferredContentSize = NSSize(width: 320, height: 240)
        let popover = NSPopover()
        popover.contentViewController = content
        defer { popover.close() }
        let rect = NSRect(x: 500, y: 650, width: 30, height: 30)
        try await BrowserExtensionPopupContentController.present(popover, relativeTo: rect, of: outside, preferredEdge: .minY)
        let container = try XCTUnwrap(popover.contentViewController)
        let keepOpen = try XCTUnwrap(button("extension.popup.keepOpen", in: container.view))
        let close = try XCTUnwrap(button("extension.popup.close", in: container.view))
        XCTAssertEqual(keepOpen.state, .off)
        XCTAssertEqual(popover.behavior, .transient)
        keepOpen.performClick(nil)
        XCTAssertEqual(popover.behavior, .applicationDefined)
        try clickPage(window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(window.firstResponder === outside)
        let draft = try await webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "unfinished entry")
        let popupWindow = try XCTUnwrap(webView.window)
        popupWindow.makeKey()
        popupWindow.makeFirstResponder(webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('draft').focus(); document.getElementById('draft').select(); true;")
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: popupWindow.windowNumber, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
        popupWindow.sendEvent(key)
        try await Task.sleep(for: .milliseconds(100))
        let edited = try await webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(edited?.count, 1, "The same popup must accept typing after returning from the page")
        XCTAssertEqual(outside.string, "Page text to copy")
        close.performClick(nil)
        XCTAssertFalse(popover.isShown)

        try await BrowserExtensionPopupContentController.present(popover, relativeTo: rect, of: outside, preferredEdge: .minY)
        XCTAssertEqual(keepOpen.state, .off, "Keep open applies only to the current presentation")
        XCTAssertEqual(popover.behavior, .transient)
        keepOpen.performClick(nil)
        keepOpen.performClick(nil)
        XCTAssertEqual(popover.behavior, .transient, "Turning Keep open off restores normal dismissal")
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: try XCTUnwrap(webView.window).windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        XCTAssertTrue(container.view.performKeyEquivalent(with: escape))
        XCTAssertFalse(popover.isShown, "Escape must dismiss the popup")
    }

    private func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityIdentifier() == identifier { return button }
        return view.subviews.lazy.compactMap { self.button(identifier, in: $0) }.first
    }

    /// A text view's mouse-down tracks the mouse until a mouse-up arrives in the
    /// event queue. Queue the mouse-up first, or the test waits forever on a
    /// machine with no real mouse input, such as CI.
    private func clickPage(_ window: NSWindow) throws {
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 50, y: 50),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        NSApp.postEvent(try event(.leftMouseUp), atStart: false)
        NSApp.sendEvent(try event(.leftMouseDown))
    }

    func testPopupCropsOnlyThePageEdgeUnderOneRoundedSurface() throws {
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
        content.preferredContentSize = content.view.frame.size
        let popover = NSPopover()
        popover.contentViewController = content
        BrowserExtensionPopupContentController.prepare(popover)
        let container = try XCTUnwrap(popover.contentViewController)
        container.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(popover.contentSize, NSSize(width: 276, height: 228))
        XCTAssertTrue(content.parent === container)
        XCTAssertTrue(content.view.superview?.superview === container.view)
        XCTAssertEqual(content.view.frame, try XCTUnwrap(content.view.superview).bounds.insetBy(dx: -2, dy: -2))
        XCTAssertEqual(content.view.frame.size, NSSize(width: 280, height: 200))
        XCTAssertEqual(container.view.layer?.cornerRadius, 14)
        XCTAssertEqual(container.view.layer?.masksToBounds, true)
        XCTAssertTrue(container.view.isFlipped)
        XCTAssertFalse(popover.animates)
    }

    func testWebKitPageResizingKeepsTheCropConstantAndUpdatesThePopover() throws {
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
        let popover = NSPopover()
        popover.contentViewController = content
        BrowserExtensionPopupContentController.prepare(popover)
        let container = try XCTUnwrap(popover.contentViewController)
        for _ in 0..<3 {
            container.preferredContentSize = NSSize(width: 320, height: 240)
            XCTAssertEqual(container.preferredContentSize, NSSize(width: 316, height: 268))
            XCTAssertEqual(popover.contentSize, NSSize(width: 316, height: 268))
        }
        BrowserExtensionPopupContentController.prepare(popover)
        XCTAssertTrue(popover.contentViewController === container)
        XCTAssertEqual(container.children.count, 1)
    }

    func testShownPopupKeepsItsPageAtTheTopWhileGrowingAndShrinking() throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }
        let anchor = try XCTUnwrap(window.contentView)
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 374, height: 250))
        content.preferredContentSize = content.view.frame.size
        let popover = NSPopover()
        popover.contentViewController = content
        BrowserExtensionPopupContentController.prepare(popover)
        defer { popover.close() }
        popover.show(relativeTo: NSRect(x: 200, y: 650, width: 30, height: 30), of: anchor, preferredEdge: .minY)
        let container = try XCTUnwrap(popover.contentViewController)
        for height in [500.0, 600.0, 320.0, 600.0, 250.0] {
            container.preferredContentSize = NSSize(width: 374, height: height)
            container.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(content.view.frame.minY, -2, accuracy: 0.5)
            XCTAssertEqual(content.view.frame.height, height, accuracy: 0.5)
            XCTAssertEqual(container.view.bounds.height, height - 4 + 32, accuracy: 0.5)
        }
    }
}
#endif
