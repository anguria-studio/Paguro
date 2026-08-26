import AppKit
import XCTest
@testable import Atoll

@MainActor
final class IslandScreenChangeMonitorTests: XCTestCase {
    func testSystemAndWorkspaceChangesAreForwarded() {
        let notificationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let monitor = IslandScreenChangeMonitor(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceCenter
        )
        var changeCount = 0
        monitor.start { changeCount += 1 }

        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        workspaceCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        XCTAssertEqual(changeCount, 3)
    }

    func testWindowChangesUseTheGivenFilter() {
        let notificationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let trackedWindow = NSWindow()
        let otherWindow = NSWindow()
        let monitor = IslandScreenChangeMonitor(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceCenter,
            windowFilter: { $0 === trackedWindow }
        )
        var changeCount = 0
        monitor.start { changeCount += 1 }

        notificationCenter.post(
            name: NSWindow.didMoveNotification,
            object: otherWindow
        )
        notificationCenter.post(
            name: NSWindow.didChangeScreenNotification,
            object: trackedWindow
        )

        XCTAssertEqual(changeCount, 1)
    }

    func testStopRemovesEveryObserver() {
        let notificationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let monitor = IslandScreenChangeMonitor(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceCenter
        )
        var changeCount = 0
        monitor.start { changeCount += 1 }
        monitor.stop()

        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        workspaceCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        XCTAssertEqual(changeCount, 0)
    }
}
