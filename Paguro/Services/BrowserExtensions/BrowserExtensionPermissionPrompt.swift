#if !APP_STORE
import AppKit

struct BrowserExtensionPermissionRequest {
    let extensionName: String
    let serviceName: String
    let permissions: [String]
    let origins: [String]
}

enum BrowserExtensionPermissionChoice: Equatable { case allow, deny, cancel }

/// One native sheet per account, with an explicit cancellation path.
@MainActor
final class BrowserExtensionPermissionPrompt {
    var presentSheet: (NSAlert, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void = {
        $0.beginSheetModal(for: $1, completionHandler: $2)
    }
    var isPresenting: Bool { finish != nil }
    private var finish: ((BrowserExtensionPermissionChoice) -> Void)?
    private weak var parent: NSWindow?
    private var alert: NSAlert?
    private var timeout: Task<Void, Never>?

    private struct Pending {
        let request: BrowserExtensionPermissionRequest
        let window: NSWindow
        let continuation: CheckedContinuation<BrowserExtensionPermissionChoice, Never>
    }
    private var queue: [Pending] = []

    func request(_ request: BrowserExtensionPermissionRequest, in window: NSWindow) async -> BrowserExtensionPermissionChoice {
        guard window.isVisible, queue.count < 4, finish != nil || window.attachedSheet == nil else { return .cancel }
        return await withCheckedContinuation { continuation in
            queue.append(Pending(request: request, window: window, continuation: continuation))
            showNext()
        }
    }

    private func showNext() {
        guard finish == nil, !queue.isEmpty else { return }
        let pending = queue.removeFirst()
        let request = pending.request, window = pending.window
        guard window.isVisible, window.attachedSheet == nil else {
            pending.continuation.resume(returning: .cancel)
            showNext()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow extra access for \(request.extensionName)?"
        alert.informativeText = "Service: \(request.serviceName)\nAllow or Deny remembers your choice for this service account. Cancel makes no change."
        let details = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 140))
        details.isEditable = false
        details.font = .systemFont(ofSize: 13)
        details.string = (request.permissions.map(Self.permissionDescription) + request.origins.map { "Website: \($0)" }).joined(separator: "\n")
        let scroll = NSScrollView(frame: details.frame)
        scroll.documentView = details
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Allow").keyEquivalent = ""
        alert.addButton(withTitle: "Deny").keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.window.defaultButtonCell = cancel.cell as? NSButtonCell
        self.alert = alert
        parent = window
        finish = { pending.continuation.resume(returning: $0) }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            self?.cancel()
        }
        presentSheet(alert, window) { [weak self, weak alert] response in
            guard let self, let alert, self.alert === alert else { return }
            self.resolve(response == .alertFirstButtonReturn ? .allow : response == .alertSecondButtonReturn ? .deny : .cancel)
        }
    }

    private static func permissionDescription(_ permission: String) -> String {
        switch permission {
        case "clipboardWrite": "Write to the clipboard (clipboardWrite)"
        case "cookies": "Read and change this service's cookies (cookies)"
        case "tabs": "Read tab details for this service (tabs)"
        case "scripting": "Run scripts on approved websites (scripting)"
        case "storage", "unlimitedStorage": "Store extension data for this service (\(permission))"
        default: "Use the \(permission) browser API"
        }
    }

    func cancel() {
        let pending = queue
        queue.removeAll()
        for request in pending { request.continuation.resume(returning: .cancel) }
        resolve(.cancel)
    }

    private func resolve(_ choice: BrowserExtensionPermissionChoice) {
        guard let finish else { return }
        self.finish = nil
        timeout?.cancel()
        timeout = nil
        if let alert, let parent, alert.window.sheetParent === parent {
            parent.endSheet(alert.window, returnCode: .abort)
            alert.window.orderOut(nil)
        }
        alert = nil
        parent = nil
        finish(choice)
        Task { @MainActor [weak self] in
            // Let AppKit finish detaching the previous sheet before presenting another.
            await Task.yield()
            self?.showNext()
        }
    }
}
#endif
