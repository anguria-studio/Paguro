# Application lifecycle

Status: active

## Purpose

Atoll can keep web services active after the main window closes. Quitting the
application is different: it must stop every service before the process exits.

## Ownership

`AtollApp` creates one `AppModel`. `AppModel` is the composition root and owns
the process-lifetime application state and presence controller.

`AppDelegate` adapts AppKit lifecycle events. Deterministic activation and
shutdown rules live in AtollCore.

`AppState` uses two startup phases. Its initializer opens the store, creates
the service graph, and loads saved values. `AppDelegate` calls `AppState.start()`
from `applicationDidFinishLaunching`. That second phase attaches platform
observers, timers, WebKit callbacks, background fetchers, and preload work.
Repeated start calls and start calls after shutdown do nothing.

The notification manager installs its macOS notification delegate while the
composition root initializes the application state. This timing allows a
notification action that launches Atoll to wait until navigation is ready.

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
After a normal launch, Atoll activates the application and orders its initial
main window forward when the SwiftUI scene makes that window available.

Before Atoll opens a main or Settings window, it changes to regular activation
and activates the application. After the final main-capable window closes, it
returns to accessory mode unless the Dock preference keeps the icon visible.
Command-Tab orders an existing visible main window forward. A Dock reopen
request also restores an existing main window or asks SwiftUI to create it.
Closing a window does not stop badge polling or notification detection.
On a fresh install, Atoll appears in both the Dock and menu bar and shows the
unread badge on its Dock icon. Existing saved choices remain unchanged.

The "Show Atoll in" setting has three modes:

- Dock only: Atoll removes the menu-bar item and keeps the Dock icon.
- Menu bar only: Atoll hides the Dock icon after the last window closes.
- Both: Atoll shows the Dock icon and the menu-bar item.

When the user drags the item off the menu bar, Atoll changes the mode to
"Dock only" so the app stays reachable.

## Quit behavior

`Command-Q` and the menu-bar Quit action both request AppKit termination.
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

AtollCore tests cover launch activation, window-close activation, Dock
preference behavior, and repeated shutdown requests. The application test
suite builds the AppKit adapter and the two-phase startup path with Swift 6
strict concurrency.
