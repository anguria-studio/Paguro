import AppKit
import Foundation
import WebKit

/// Presents native file pickers and JavaScript dialogs for a web view.
@MainActor
final class WebDialogPresenter {
    /// Presents a file picker that respects the page's directory and multiple
    /// selection options.
    func presentOpenPanel(
        with parameters: WKOpenPanelParameters,
        over webView: WKWebView,
        completion: @escaping @MainActor ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true

        let session = ModalSession(cancelValue: [URL]?.none, completion)
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            session.finish(response == .OK ? panel.urls : nil)
        }

        if let window = webView.window {
            session.observeClose(of: window)
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            panel.begin(completionHandler: handleResponse)
        }
    }

    func presentAlert(
        message: String,
        over webView: WKWebView,
        completion: @escaping @MainActor () -> Void
    ) {
        AppLogger.webView.info("JS alert panel")
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")

        let session = ModalSession<Void>(cancelValue: (), { _ in completion() })
        present(alert, over: webView, session: session) { _ in () }
    }

    func presentConfirm(
        message: String,
        over webView: WKWebView,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        AppLogger.webView.info("JS confirm panel")
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let session = ModalSession(cancelValue: false, completion)
        present(alert, over: webView, session: session) { $0 == .alertFirstButtonReturn }
    }

    func presentPrompt(
        prompt: String,
        defaultText: String?,
        over webView: WKWebView,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        AppLogger.webView.info("JS text-input panel")
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let session = ModalSession(cancelValue: String?.none, completion)
        present(alert, over: webView, session: session) { response in
            response == .alertFirstButtonReturn ? field.stringValue : nil
        }
    }

    /// Presents an alert as a sheet when possible and as an app-modal panel for
    /// a web view without a host window, such as an authentication popup.
    private func present<Value>(
        _ alert: NSAlert,
        over webView: WKWebView,
        session: ModalSession<Value>,
        map: @escaping (NSApplication.ModalResponse) -> Value
    ) {
        if let window = webView.window {
            session.observeClose(of: window)
            alert.beginSheetModal(for: window) { response in
                session.finish(map(response))
            }
        } else {
            session.finish(map(alert.runModal()))
        }
    }
}

/// Resolves an AppKit modal interaction exactly once. Closing the host window
/// resolves it with the supplied cancellation value.
@MainActor
private final class ModalSession<Value> {
    private var completion: (@MainActor (Value) -> Void)?
    private var closeObserver: NSObjectProtocol?
    private let cancelValue: Value

    init(cancelValue: Value, _ completion: @escaping @MainActor (Value) -> Void) {
        self.cancelValue = cancelValue
        self.completion = completion
    }

    func observeClose(of window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.finish(self.cancelValue)
            }
        }
    }

    func finish(_ value: Value) {
        guard let completion else { return }
        self.completion = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        completion(value)
    }
}
