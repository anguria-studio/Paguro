# Application lifecycle

Status: active

## Purpose

Paguro can keep web services active after the main window closes. Quitting the
application is different: it must stop every service before the process exits.

## Ownership

`PaguroApp` creates one `AppModel`. `AppModel` is the composition root and owns
the process-lifetime application state and presence controller.

`AppDelegate` adapts AppKit lifecycle events. Deterministic activation and
shutdown rules live in PaguroCore.

`AppState` uses two startup phases. Its initializer opens the store, creates
the service graph, and loads saved values. `AppDelegate` calls `AppState.start()`
from `applicationDidFinishLaunching`. That second phase attaches platform
observers, timers, WebKit callbacks, background fetchers, and preload work.
Repeated start calls and start calls after shutdown do nothing.

`NotificationRuntime.start()` installs the macOS notification delegate after
AppKit finishes launching, then connects the navigation observers. It starts
authorization one task turn later. The composition root does not access
`UNUserNotificationCenter` during initialization.

`StoreLoader` opens or repairs the SwiftData store.
`StoreRecoveryCoordinator` then prepares any recovery notice and backup picker.
It applies a selected backup only after restart, before the store opens again.
The main window offers backup selection when it detects possible data loss
and finds a useful recovery candidate. Settings uses configuration export and
import for manual setup copies; automatic snapshots remain a recovery feature.

`HibernationScheduler` owns idle sweeps and immediate-hibernation grace tasks.
It cancels all scheduled work before the web-view pool shuts down.
`NotificationRuntime` owns notification polling, quiet-hours timing, network
and sleep suspension, unread badge probes, and click-routing observers. It
removes these callbacks and observers before the web-view pool shuts down.

## Window behavior

A normal launch uses regular activation. A login-item launch starts in
accessory mode unless the user explicitly keeps the Dock icon visible.
After a normal launch, Paguro activates the application and orders its initial
main window forward when the SwiftUI scene makes that window available.

Before Paguro opens a main or Settings window, it changes to regular activation
and activates the application. After the final main-capable window closes, it
returns to accessory mode unless the Dock preference keeps the icon visible.
Command-Tab orders an existing visible main window forward. When no visible
main-capable window exists, Command-Tab brings the main window back. Command-Tab
sends no reopen request, so the activation is the only signal for this route. A
visible Settings window counts as a visible window, and it keeps the main window
closed.

An activation that Paguro requests for itself restores no window. Such a request
always precedes a window that Paguro is about to show, such as the Settings
window of the menu-bar button. A restored main window would cover that window.
The request marks itself for the activation that follows, and the mark expires
after two seconds. A request that reaches no activation therefore cannot hide a
later Command-Tab.

A Dock reopen request also restores an existing main window or asks SwiftUI to
create it. A Dock click can run the reopen handler and the activation restore.
Both repeat safely, because the main window scene is unique and a second order
request for the same window changes nothing.

Four routes reach the main window from outside it. A Dock reopen request is one
of them. The other three are the app-name button in the menu-bar header, a
click on an island alert, and a click on a macOS notification. These three share
one route. That route promotes the activation policy. It then orders an existing
main window forward, or asks SwiftUI to build the window again. Only SwiftUI can
build the window of its own scene, so the view layer gives `AppDelegate` that
action.
Closing a window does not stop badge polling or notification detection.
On a fresh install, Paguro appears in both the Dock and menu bar and shows the
unread badge on its Dock icon. Existing saved choices remain unchanged.

Settings exposes two switches:

- Show in menu bar adds or removes the menu-bar item.
- Hide Dock icon when the window is closed appears only while the menu-bar
  item is enabled. It hides the Dock icon after the last window closes.
  Opening a window restores the Dock icon.

Existing saved modes remain compatible. Dock only turns the first switch off.
Both turns only the first switch on. Menu bar only turns both switches on.
Turning off Show in menu bar also keeps the Dock icon visible so the app stays
reachable. Turning it back on leaves Dock hiding off until the user enables it.
Dragging the item off the menu bar applies the same safe behavior.

The menu-bar item uses the Paguro shell template. macOS supplies its tint for
light and dark menu bars. The vector has thin transparent spiral seams on a
20 point canvas. The status item uses 45 percent opacity when global mute or
quiet hours are active, or all configured services are effectively muted.
An empty service list alone does not dim the icon.

The menu-bar item opens a native status window. The window can select a
service, toggle global notification mute, lock Paguro, open the main window,
or open Settings. This window is the complete application route
while Paguro runs with its Dock icon hidden.

## First run

A window with no service shows the first-run welcome screen in place of the
shell. `FirstRunPolicy` in PaguroCore holds the rule, and it counts the
services of every workspace together. The screen carries the notification
permission and the island offers, so Paguro has no separate welcome sheet and
stores no "seen" state for one.

A new install has no workspace and no service. Launch never seeds data.
The wizard collects a workspace name, service selections, and appearance.
The name defaults to Personal. `AppState.addSetupServices` sends the complete
selection to `WorkspaceStore.addServices`, which saves the named workspace and
its accounts in one transaction. Back and step navigation do not save accounts.
A failed save keeps the draft available for retry.
Store recovery still uses `hasEverHadData`, snapshots, and the saved content
record to detect data loss. Any workspace now counts as user data.

The window reads the rule at each render, so the first service ends the screen
without another signal. `NotificationRuntime.start()` still owns the macOS
permission request for every launch, including a login-item launch that opens
no window. See [Native shell](NATIVE_SHELL.md) and
[Notification system](NOTIFICATIONS.md).

## App lock

A launch that starts locked shows the lock screen first. The first-run screen
waits under it and appears after the unlock, and none of its actions can run
while the window is locked.

Locking suppresses island alerts and macOS notification banners and sounds.
The island hides immediately and retains its recent history in memory. Paguro removes
its pending and delivered macOS notifications. Unlocking permits new alerts
and restores the existing island history in the collapsed state, without
replaying compact alerts or events suppressed during lock.
The lock transition applies to manual lock, launch lock, and sleep lock.
The menu-bar header Lock button uses this transition and closes the menu. It
appears only when App Lock is enabled and Paguro is unlocked. File > Lock Now
(Command-Shift-L) also requires App Lock to be enabled.

The lock screen waits for the user to activate Unlock before it requests
Touch ID or the Mac login password. Showing the screen after manual lock,
launch, sleep, or reopening a window does not start authentication.
Cancelling authentication keeps the app locked; Unlock starts another attempt.

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

The quiet-hours timer checks cancellation and shutdown after each wait. A wait
can finish before cancellation while its continuation is still queued. That
continuation must not query the store or refresh mute state after shutdown.

Service work stops after termination. Sparkle can use a temporary installer
helper to finish an update in the direct build. This helper does not run
services or notification polling.

## Verification

PaguroCore tests cover launch activation, window-close activation, the window
restore on activation, Dock preference behavior, and repeated shutdown requests. The application test
suite builds the AppKit adapter and the two-phase startup path with Swift 6
strict concurrency.
