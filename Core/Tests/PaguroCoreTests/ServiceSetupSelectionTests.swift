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
}
