import Foundation
import Observation
import PaguroCore

/// Persists the app-wide explanation separately from service accounts.
@MainActor
@Observable
final class PasskeyNoticeController {
    private(set) var state: PasskeyNoticeState
    private let defaults: UserDefaults

    init(defaults: UserDefaults, hasLegacySeenNotice: Bool) {
        self.defaults = defaults
        let seen = defaults.bool(forKey: DefaultsKey.passkeyNoticeSeen) || hasLegacySeenNotice
        state = PasskeyNoticeState(hasBeenSeen: seen)
        if seen { defaults.set(true, forKey: DefaultsKey.passkeyNoticeSeen) }
    }

    func present(isLocked: Bool, passkeysSupported: Bool) {
        state.present(isLocked: isLocked, passkeysSupported: passkeysSupported)
        if state.hasBeenSeen { defaults.set(true, forKey: DefaultsKey.passkeyNoticeSeen) }
    }

    func dismiss() {
        state.dismiss()
    }
}
