#if DEBUG
import Foundation

/// Fictional content for screenshots, separate from service notification detection.
///
/// The type lives in the app target because only this target defines `DEBUG` in
/// the `Debug` and in the custom `Compatibility` configuration. Xcode does not
/// pass a custom debug configuration to Swift package targets, so the same guard
/// in `PaguroCore` removed the type from a `Compatibility` build. A Release build
/// compiles nothing from this file, so no demo text reaches a released binary.
struct IslandPreviewNotifications: Sendable {
    static let launchArgument = "--paguro-demo-notifications"

    struct Account: Sendable {
        let serviceID: UUID
        let catalogID: String?

        init(serviceID: UUID, catalogID: String?, url: String) {
            self.serviceID = serviceID
            self.catalogID = catalogID ?? Self.catalogID(for: url)
        }

        // Custom accounts can use these services without a catalog reference.
        private static func catalogID(for url: String) -> String? {
            guard let host = URL(string: url)?.host?.lowercased() else { return nil }
            switch host {
            case "mail.google.com": return "gmail"
            case "web.whatsapp.com": return "whatsapp"
            case "slack.com": return "slack"
            default: return host.hasSuffix(".slack.com") ? "slack" : nil
            }
        }
    }

    struct Message: Equatable, Sendable {
        let catalogID: String
        let title: String
        let body: String
    }

    struct Selection: Sendable {
        let serviceID: UUID
        let message: Message
    }

    static let messages: [Message] = [
        Message(catalogID: "whatsapp", title: "Alex Morgan",
                body: "Are we still on for coffee at 4?"),
        Message(catalogID: "whatsapp", title: "Weekend plans",
                body: "Mia: Saturday by the sea? I'll bring snacks."),
        Message(catalogID: "whatsapp", title: "Sam Rivera",
                body: "Just arrived. See you in a minute!"),
        Message(catalogID: "whatsapp", title: "Dinner tonight",
                body: "Jordan: Table booked for 7. See you there!"),
        Message(catalogID: "slack", title: "Alex in #design",
                body: "The new mockups are ready for a quick look."),
        Message(catalogID: "slack", title: "Mia in #team",
                body: "Small win: we shipped the new homepage!"),
        Message(catalogID: "slack", title: "Jordan Lee",
                body: "Left a few notes on the latest prototype."),
        Message(catalogID: "slack", title: "Sam in #general",
                body: "Quick sync in ten minutes?"),
        Message(catalogID: "gmail", title: "Nora Chen",
                body: "Friday plans — I've sent over a few ideas."),
        Message(catalogID: "gmail", title: "Studio North",
                body: "Your project files are ready to download."),
        Message(catalogID: "gmail", title: "The Reading Room",
                body: "This week's picks: a little inspiration."),
        Message(catalogID: "gmail", title: "Alex Morgan",
                body: "Design review — here's the updated agenda.")
    ]

    private var lastMessage: Message?

    init() {}

    mutating func next(
        accounts: [Account],
        using generator: inout some RandomNumberGenerator
    ) -> Selection? {
        let catalogIDs = Set(accounts.compactMap(\.catalogID))
        let available = Self.messages.filter { catalogIDs.contains($0.catalogID) }
        let candidates = available.count > 1
            ? available.filter { $0 != lastMessage }
            : available
        guard let message = candidates.randomElement(using: &generator),
              let account = accounts.filter({ $0.catalogID == message.catalogID })
                .randomElement(using: &generator) else { return nil }
        lastMessage = message
        return Selection(serviceID: account.serviceID, message: message)
    }
}
#endif
