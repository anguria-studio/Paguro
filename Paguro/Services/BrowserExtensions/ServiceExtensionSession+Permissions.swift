#if !APP_STORE
import AppKit
import PaguroCore
import WebKit

/// Optional access: WebKit asks, the account's native sheet answers, and the
/// manager saves the choice before WebKit grants anything.
@available(macOS 15.4, *)
extension ServiceExtensionSession {
    private static let maximumRequestSize = 128

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        // Every requested permission must be declared optional. Native messaging never is.
        let eligible = permissions
            .intersection(context.webExtension.optionalPermissions)
            .subtracting([.nativeMessaging])
        guard eligible == permissions, !eligible.isEmpty else { return ([], nil) }
        let allowed = await requestOptionalAccess(permissions: Set(eligible.map(\.rawValue)), origins: [],
                                                  context: context, tab: tab)
        return (allowed ? eligible : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let declared = context.webExtension.optionalPermissionMatchPatterns
        guard !patterns.isEmpty, patterns.count <= Self.maximumRequestSize,
              patterns.allSatisfy({ requested in declared.contains { $0.matches(requested) } }) else {
            return ([], nil)
        }
        let allowed = await requestOptionalAccess(permissions: [], origins: Set(patterns.map(\.string)),
                                                  context: context, tab: tab)
        return (allowed ? patterns : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        guard !urls.isEmpty, urls.count <= Self.maximumRequestSize else { return ([], nil) }
        // The sheet and the saved choice name the whole host, so the user sees
        // exactly what a later visit to that host will be allowed to do.
        let declared = context.webExtension.optionalPermissionMatchPatterns
        var patterns: Set<String> = []
        for url in urls {
            guard let pattern = Self.hostPattern(for: url, declared: declared) else { return ([], nil) }
            patterns.insert(pattern.string)
        }
        let allowed = await requestOptionalAccess(permissions: [], origins: patterns, context: context, tab: tab)
        return (allowed ? urls : [], nil)
    }

    private static func hostPattern(for url: URL,
                                    declared: Set<WKWebExtension.MatchPattern>) -> WKWebExtension.MatchPattern? {
        guard url.absoluteString.utf8.count <= 8_192, url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, declared.contains(where: { $0.matches(url) }),
              let pattern = try? WKWebExtension.MatchPattern(string: "\(scheme)://\(host)/*"),
              declared.contains(where: { $0.matches(pattern) }) else { return nil }
        return pattern
    }

    private func requestOptionalAccess(permissions: Set<String>, origins: Set<String>,
                                       context: WKWebExtensionContext,
                                       tab: (any WKWebExtensionTab)?) async -> Bool {
        guard permissions.count + origins.count <= Self.maximumRequestSize,
              let id = contexts.first(where: { $0.value === context })?.key,
              let saved = optionalChoices[id], saved.isValid,
              let window = permissionWindow(for: context, in: tab) else { return false }
        // A remembered denial answers without a new sheet.
        let isDenied = !permissions.isDisjoint(with: saved.deniedPermissions)
            || !origins.isDisjoint(with: saved.deniedOrigins)
        guard !isDenied else { return false }
        var candidate = saved
        candidate.record(permissions: permissions, origins: origins, allowed: true)
        guard candidate.isValid else { return false }

        let epoch = permissionEpoch
        let popup = context.action(for: self)?.popupPopover
        holdPermissionPopup(popup)
        defer { releasePermissionPopup(popup) }
        let request = BrowserExtensionPermissionRequest(
            extensionName: context.webExtension.displayName ?? "Extension", serviceName: permissionServiceName,
            permissions: permissions.sorted(), origins: origins.sorted())
        let choice = await permissionPrompt.request(request, in: window)

        // The account can change while the sheet is open. A stale answer grants nothing.
        guard choice != .cancel, !Task.isCancelled, window.isVisible,
              permissionRequestIsCurrent(epoch, context: context),
              var access = optionalChoices[id] else { return false }
        access.record(permissions: permissions, origins: origins, allowed: choice == .allow)
        guard access.isValid, saveOptionalAccess(id, access) else { return false }
        optionalChoices[id] = access
        if choice == .deny { applyOptionalAccess(access, to: context) }
        return choice == .allow
    }

    /// The requesting popup must stay open while its sheet waits, or WebKit
    /// would tear down the JavaScript that asked.
    private func holdPermissionPopup(_ popup: NSPopover?) {
        guard let popup, popup.isShown else { return }
        let key = ObjectIdentifier(popup)
        var hold = permissionPopupHolds[key] ?? (popover: popup, behavior: popup.behavior, count: 0)
        hold.count += 1
        permissionPopupHolds[key] = hold
        popup.behavior = .applicationDefined
    }

    private func releasePermissionPopup(_ popup: NSPopover?) {
        guard let popup, let hold = permissionPopupHolds[ObjectIdentifier(popup)] else { return }
        if hold.count > 1 {
            permissionPopupHolds[ObjectIdentifier(popup)]?.count -= 1
        } else {
            permissionPopupHolds[ObjectIdentifier(popup)] = nil
            if popup.isShown { popup.behavior = hold.behavior }
        }
    }

    func applyOptionalAccess(_ access: ExtensionOptionalAccess?, to context: WKWebExtensionContext) {
        isApplyingOptionalAccess = true
        defer { isApplyingOptionalAccess = false }
        let webExtension = context.webExtension

        let declaredOptional = Set(webExtension.optionalPermissions.map(\.rawValue))
        let approved = (access?.permissions ?? []).intersection(declaredOptional).subtracting(["nativeMessaging"])
        let permissions = webExtension.requestedPermissions
            .union(approved.map(WKWebExtension.Permission.init(rawValue:)))
        context.grantedPermissions = Self.permanent(permissions)
        // Keep denials in the host. Some engines report success for a request
        // filtered out by native explicit denial, even though access is absent.
        context.deniedPermissions = [:]

        let approvedOrigins = (access?.origins ?? [])
            .compactMap { try? WKWebExtension.MatchPattern(string: $0) }
            .filter { pattern in webExtension.optionalPermissionMatchPatterns.contains { $0.matches(pattern) } }
        context.grantedPermissionMatchPatterns = Self.permanent(
            webExtension.allRequestedMatchPatterns.union(approvedOrigins))
        context.deniedPermissionMatchPatterns = [:]
    }

    private static func permanent<Key: Hashable>(_ keys: Set<Key>) -> [Key: Date] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, Date.distantFuture) })
    }

    func resetOptionalAccess(_ id: UUID) {
        permissionEpoch = UUID()
        permissionPrompt.cancel()
        guard let context = contexts[id], let old = optionalChoices[id] else { return }
        let access = ExtensionOptionalAccess(packageSHA256: old.packageSHA256)
        optionalChoices[id] = access
        applyOptionalAccess(access, to: context)
    }

    /// The extension gave up access itself, through `permissions.remove`.
    @objc func optionalAccessRemoved(_ notification: Notification) {
        guard !isApplyingOptionalAccess, let context = notification.object as? WKWebExtensionContext,
              let id = contexts.first(where: { $0.value === context })?.key,
              var access = optionalChoices[id] else { return }
        access.permissions.formIntersection(Set(context.currentPermissions.map(\.rawValue)))
        access.origins.formIntersection(Set(context.currentPermissionMatchPatterns.map(\.string)))
        guard access != optionalChoices[id] else { return }
        optionalChoices[id] = access
        _ = saveOptionalAccess(id, access)
    }
}
#endif
