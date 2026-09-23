import Foundation
import Observation
import PaguroCore

/// Stores the default destination for outside web links.
@MainActor
@Observable
final class LinkOpeningSettings {
    private(set) var opensInPaguro: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        opensInPaguro = defaults.bool(forKey: DefaultsKey.openExternalLinksInApp)
    }

    func setOpensInPaguro(_ enabled: Bool) {
        opensInPaguro = enabled
        defaults.set(enabled, forKey: DefaultsKey.openExternalLinksInApp)
    }

    func opensInPaguro(serviceOverride: Bool?) -> Bool {
        LinkOpeningPolicy(override: serviceOverride).opensInPaguro(globalDefault: opensInPaguro)
    }
}
