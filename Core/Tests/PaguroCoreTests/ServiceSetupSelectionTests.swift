import XCTest
@testable import PaguroCore

final class ServiceSetupSelectionTests: XCTestCase {
    func testTogglingPreservesSelectionOrderWithoutDuplicates() {
        let mail = ServiceSetupDraft(id: "mail", label: "Mail", url: "https://mail.example")
        let chat = ServiceSetupDraft(id: "chat", label: "Chat", url: "https://chat.example")
        var selection = ServiceSetupSelection()
        selection.toggle(mail)
        selection.toggle(chat)
        XCTAssertEqual(selection.services, [mail, chat])
        selection.toggle(mail)
        XCTAssertEqual(selection.services, [chat])
        selection.toggle(mail)
        XCTAssertEqual(selection.services, [chat, mail])
    }

    func testCustomWebsitesCanUseTheSameAddressAsSeparateAccounts() {
        var selection = ServiceSetupSelection()
        let personal = ServiceSetupDraft(label: "Personal", url: "https://mail.example")
        let work = ServiceSetupDraft(label: "Work", url: "https://mail.example")
        selection.toggle(personal)
        selection.toggle(work)
        XCTAssertEqual(selection.services.count, 2)
        selection.toggle(personal)
        XCTAssertEqual(selection.services, [work])
    }
    func testUncheckedCustomCardRemainsAvailableWithItsIcon() {
        let draft = ServiceSetupDraft(label: "Notes", url: "https://notes.example", customIconData: Data([1, 2]))
        var selection = ServiceSetupSelection()
        selection.toggle(draft)
        selection.toggle(draft)
        XCTAssertTrue(selection.services.isEmpty)
        XCTAssertEqual(selection.customWebsites, [draft])
        selection.toggle(draft)
        XCTAssertEqual(selection.services, [draft])
        XCTAssertEqual(selection.customWebsites, [draft])
    }

    func testCustomSearchMatchesNamesAndAddressesEvenWhenUnchecked() {
        let draft = ServiceSetupDraft(label: "Café Work", url: "https://portal.example/team")
        var selection = ServiceSetupSelection()
        selection.toggle(draft)
        selection.toggle(draft)
        XCTAssertEqual(selection.matchingCustomWebsites(search: "  CAFE  "), [draft])
        XCTAssertEqual(selection.matchingCustomWebsites(search: "PORTAL.EXAMPLE"), [draft])
        XCTAssertEqual(selection.matchingCustomWebsites(search: "team"), [draft])
        XCTAssertEqual(selection.matchingCustomWebsites(search: "  "), [draft])
        XCTAssertTrue(selection.matchingCustomWebsites(search: "absent").isEmpty)
        XCTAssertTrue(selection.services.isEmpty)
    }

    func testCatalogSelectionsDoNotBecomeCustomCards() {
        var selection = ServiceSetupSelection()
        selection.toggle(ServiceSetupDraft(id: "gmail", label: "Gmail", url: "https://mail.google.com", catalogEntryID: "gmail"))
        XCTAssertTrue(selection.customWebsites.isEmpty)
        XCTAssertEqual(selection.services.count, 1)
    }
}
