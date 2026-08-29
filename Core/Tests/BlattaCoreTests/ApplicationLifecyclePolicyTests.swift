import Testing
@testable import BlattaCore

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

    @Test("A launch that already reached the front asks for nothing")
    func settledLaunchAsksForNothing() {
        let activation = ApplicationLifecyclePolicy.initialWindowActivation(
            isApplicationActive: true,
            isMainWindowKey: true
        )
        #expect(!activation.activatesApplication)
        #expect(!activation.ordersWindowForward)
    }

    @Test("A launch behind another application asks for the front and the window")
    func launchBehindAnotherApplicationAsksForBoth() {
        let activation = ApplicationLifecyclePolicy.initialWindowActivation(
            isApplicationActive: false,
            isMainWindowKey: false
        )
        #expect(activation.activatesApplication)
        #expect(activation.ordersWindowForward)
    }

    @Test("An active launch with no key window orders only the window forward")
    func activeLaunchWithoutKeyWindowOrdersTheWindow() {
        let activation = ApplicationLifecyclePolicy.initialWindowActivation(
            isApplicationActive: true,
            isMainWindowKey: false
        )
        #expect(!activation.activatesApplication)
        #expect(activation.ordersWindowForward)
    }

    @Test("A regular launch settles only after the window has taken the front")
    func regularLaunchSettlesAfterTheWindowTakesTheFront() {
        #expect(!ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: .regular,
            hasActivatedSinceLaunch: false,
            isAwaitingInitialWindowActivation: false,
            isSettlingLoginLaunch: false,
            hasMainWindow: true
        ))
        #expect(!ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: .regular,
            hasActivatedSinceLaunch: true,
            isAwaitingInitialWindowActivation: true,
            isSettlingLoginLaunch: false,
            hasMainWindow: true
        ))
        #expect(!ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: .regular,
            hasActivatedSinceLaunch: true,
            isAwaitingInitialWindowActivation: false,
            isSettlingLoginLaunch: false,
            hasMainWindow: false
        ))
        #expect(ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: .regular,
            hasActivatedSinceLaunch: true,
            isAwaitingInitialWindowActivation: false,
            isSettlingLoginLaunch: false,
            hasMainWindow: true
        ))
    }

    @Test("A login launch settles without a window and without activation")
    func loginLaunchSettlesWithoutAWindow() {
        #expect(!ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: .accessory,
            hasActivatedSinceLaunch: false,
            isAwaitingInitialWindowActivation: false,
            isSettlingLoginLaunch: true,
            hasMainWindow: false
        ))
        #expect(ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: .accessory,
            hasActivatedSinceLaunch: false,
            isAwaitingInitialWindowActivation: false,
            isSettlingLoginLaunch: false,
            hasMainWindow: false
        ))
    }

    @Test("A user action from an active Blatta needs no activation request")
    func userActionWhileActiveNeedsNoRequest() {
        #expect(ApplicationLifecyclePolicy.activationRequestForUserAction(
            isApplicationActive: true,
            hasOtherFrontApplication: true
        ) == .none)
    }

    @Test("A user action takes the front from the application that holds it")
    func userActionTakesTheFront() {
        #expect(ApplicationLifecyclePolicy.activationRequestForUserAction(
            isApplicationActive: false,
            hasOtherFrontApplication: true
        ) == .takeFront)
    }

    @Test("A user action with no other front application asks cooperatively")
    func userActionWithoutAFrontApplicationAsksCooperatively() {
        #expect(ApplicationLifecyclePolicy.activationRequestForUserAction(
            isApplicationActive: false,
            hasOtherFrontApplication: false
        ) == .cooperative)
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
