import Testing
@testable import AtollCore

@Suite("Application lifecycle policy")
struct ApplicationLifecyclePolicyTests {
    @Test("A login launch starts as an accessory")
    func loginLaunchStartsAccessory() {
        #expect(ApplicationLifecyclePolicy.activationAtLaunch(
            launchedAsLoginItem: true,
            keepsDockIconVisible: false
        ) == .accessory)
    }

    @Test("A direct launch and a requested Dock icon start regular")
    func visibleLaunchesStartRegular() {
        #expect(ApplicationLifecyclePolicy.activationAtLaunch(
            launchedAsLoginItem: false,
            keepsDockIconVisible: false
        ) == .regular)
        #expect(ApplicationLifecyclePolicy.activationAtLaunch(
            launchedAsLoginItem: true,
            keepsDockIconVisible: true
        ) == .regular)
    }

    @Test("Showing a main window uses regular activation")
    func showingWindowUsesRegularActivation() {
        #expect(ApplicationLifecyclePolicy.activationBeforeShowingMainWindow() == .regular)
    }

    @Test("Closing the final main window returns to accessory mode")
    func closingFinalWindowReturnsAccessory() {
        #expect(ApplicationLifecyclePolicy.activationAfterClosingMainWindow(
            visibleMainWindowCount: 0,
            keepsDockIconVisible: false
        ) == .accessory)
        #expect(ApplicationLifecyclePolicy.activationAfterClosingMainWindow(
            visibleMainWindowCount: 1,
            keepsDockIconVisible: false
        ) == .regular)
        #expect(ApplicationLifecyclePolicy.activationAfterClosingMainWindow(
            visibleMainWindowCount: 0,
            keepsDockIconVisible: true
        ) == .regular)
    }

    @Test("Shutdown starts and finishes once")
    func shutdownIsIdempotent() {
        var state = ApplicationShutdownState()

        let firstBegin = state.begin()
        #expect(firstBegin)
        #expect(state.phase == .stopping)
        let secondBegin = state.begin()
        #expect(!secondBegin)

        state.finish()
        #expect(state.phase == .stopped)
        let finalBegin = state.begin()
        #expect(!finalBegin)
    }
}
