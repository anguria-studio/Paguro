import Testing
@testable import PaguroCore

struct ChatAppRuleTests {
    @Test
    func overrideOnMakesACustomServiceAChatApp() {
        #expect(ChatAppRule.isChatApp(override: true, catalogCategory: nil))
    }

    @Test
    func overrideOffRemovesACatalogMessagingService() {
        #expect(ChatAppRule.isChatApp(override: false, catalogCategory: "Messaging") == false)
    }

    @Test
    func noOverrideFollowsTheCatalogCategory() {
        #expect(ChatAppRule.isChatApp(override: nil, catalogCategory: "Messaging"))
        #expect(ChatAppRule.isChatApp(override: nil, catalogCategory: "Email") == false)
        #expect(ChatAppRule.isChatApp(override: nil, catalogCategory: nil) == false)
    }
}
