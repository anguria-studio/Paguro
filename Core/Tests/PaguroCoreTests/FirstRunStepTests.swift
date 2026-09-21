import XCTest
@testable import PaguroCore

final class FirstRunStepTests: XCTestCase {
    func testCurrentStepNeverNavigates() {
        for step in FirstRunStep.allCases {
            XCTAssertFalse(step.canNavigate(to: step, canCreateWorkspace: true))
            XCTAssertFalse(step.canNavigate(to: step, canCreateWorkspace: false))
        }
    }

    func testEarlierStepsRemainAvailableWithAnIncompleteDraft() {
        XCTAssertTrue(FirstRunStep.appearance.canNavigate(to: .workspace, canCreateWorkspace: false))
        XCTAssertTrue(FirstRunStep.appearance.canNavigate(to: .welcome, canCreateWorkspace: false))
        XCTAssertTrue(FirstRunStep.workspace.canNavigate(to: .welcome, canCreateWorkspace: false))
    }

    func testWorkspaceDoesNotRequireAServiceSelection() {
        XCTAssertTrue(FirstRunStep.welcome.canNavigate(to: .workspace, canCreateWorkspace: false))
    }

    func testAppearanceUsesTheSameDraftValidationAsContinue() {
        var draft = ServiceSetupSelection()
        for source in [FirstRunStep.welcome, .workspace] {
            XCTAssertFalse(source.canNavigate(to: .appearance, canCreateWorkspace: draft.canCreateWorkspace))
        }
        let service = ServiceSetupDraft(id: "mail", label: "Mail", url: "https://example.com")
        draft.toggle(service)
        for source in [FirstRunStep.welcome, .workspace] {
            XCTAssertTrue(source.canNavigate(to: .appearance, canCreateWorkspace: draft.canCreateWorkspace))
        }
        draft.workspaceName = "  "
        XCTAssertFalse(FirstRunStep.workspace.canNavigate(to: .appearance, canCreateWorkspace: draft.canCreateWorkspace))
        draft.workspaceName = "Personal"
        draft.toggle(service)
        XCTAssertFalse(FirstRunStep.workspace.canNavigate(to: .appearance, canCreateWorkspace: draft.canCreateWorkspace))
    }
}
