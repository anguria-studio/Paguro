# Application lifecycle

Status: active

## Purpose

Blatta can keep web services active after the main window closes. Quitting the
application is different: it must stop every service before the process exits.

## Ownership

`BlattaApp` creates one `AppModel`. `AppModel` is the composition root and owns
the process-lifetime application state and presence controller.

`AppDelegate` adapts AppKit lifecycle events. Deterministic activation and
shutdown rules live in BlattaCore.

`AppState` uses two startup phases. Its initializer opens the store, creates
the service graph, and loads saved values. `AppDelegate` calls `AppState.start()`
from `applicationDidFinishLaunching`. That second phase attaches platform
observers, timers, WebKit callbacks, background fetchers, and preload work.
Repeated start calls and start calls after shutdown do nothing.

The notification manager installs its macOS notification delegate while the
composition root initializes the application state. This timing allows a
notification action that launches Blatta to wait until navigation is ready.

`StoreLoader` opens or repairs the SwiftData store.
`StoreRecoveryCoordinator` then prepares any recovery notice and backup picker.
It applies a selected backup only after restart, before the store opens again.
`HibernationScheduler` owns idle sweeps and immediate-hibernation grace tasks.
It cancels all scheduled work before the web-view pool shuts down.
`NotificationRuntime` owns notification polling, quiet-hours timing, network
and sleep suspension, unread badge probes, and click-routing observers. It
removes these callbacks and observers before the web-view pool shuts down.

## Window behavior

A normal launch uses regular activation. A login-item launch starts in
accessory mode unless the user explicitly keeps the Dock icon visible.
After a normal launch, Blatta activates the application and orders its initial
main window forward when the SwiftUI scene makes that window available.

Before Blatta opens a main or Settings window, it changes to regular activation
and activates the application. After the final main-capable window closes, it
returns to accessory mode unless the Dock preference keeps the icon visible.
Command-Tab orders an existing visible main window forward. When no visible
main-capable window exists, Command-Tab brings the main window back. Command-Tab
sends no reopen request, so the activation is the only signal for this route. A
visible Settings window counts as a visible window, and it keeps the main window
closed.

An activation that Blatta requests for itself restores no window. Such a request
always precedes a window that Blatta is about to show, such as the Settings
window of the menu-bar button. A restored main window would cover that window.
The request marks itself for the activation that follows, and the mark expires
after two seconds. A request that reaches no activation therefore cannot hide a
later Command-Tab.

A Dock reopen request also restores an existing main window or asks SwiftUI to
create it. A Dock click can run the reopen handler and the activation restore.
Both repeat safely, because the main window scene is unique and a second order
request for the same window changes nothing.

Four routes reach the main window from outside it. A Dock reopen request is one
of them. The other three are the "Open Blatta" button of the menu-bar window, a
click on an island alert, and a click on a macOS notification. These three share
one route. That route promotes the activation policy. It then orders an existing
main window forward, or asks SwiftUI to build the window again. Only SwiftUI can
build the window of its own scene, so the view layer gives `AppDelegate` that
action.
Closing a window does not stop badge polling or notification detection.
On a fresh install, Blatta appears in both the Dock and menu bar and shows the
unread badge on its Dock icon. Existing saved choices remain unchanged.

The "Show Blatta in" setting has three modes:

- Dock only: Blatta removes the menu-bar item and keeps the Dock icon.
- Menu bar only: Blatta hides the Dock icon after the last window closes.
- Both: Blatta shows the Dock icon and the menu-bar item.

When the user drags the item off the menu bar, Blatta changes the mode to
"Dock only" so the app stays reachable.

The menu-bar item opens a native status window. The window can select a
service, toggle global notification mute, open the main window, open Settings,
or change a presence preference. This window is the complete application route
while Blatta runs in Menu bar only mode.

## Quit behavior

`Command-Q` and the application menu Quit action both request AppKit termination.
`AppDelegate` returns `terminateLater`, waits for `AppModel.shutdown()`, and
then replies to AppKit.

Shutdown is idempotent. It performs these actions:

1. Cancel application timers and pending hibernation work.
2. Stop notification polling and transient badge fetches.
3. Stop network and content-blocker work.
4. Cancel every download in progress, including downloads from a web view
   that hibernation already removed.
5. Stop and release every live web view.
6. Remove notification observers.
7. Save the selected space and service, then ask `StoreRecoveryCoordinator` to
   record the store content.

The process has no helper that continues after termination.

## Verification

BlattaCore tests cover launch activation, window-close activation, the window
restore on activation, Dock preference behavior, and repeated shutdown requests. The application test
suite builds the AppKit adapter and the two-phase startup path with Swift 6
strict concurrency.
