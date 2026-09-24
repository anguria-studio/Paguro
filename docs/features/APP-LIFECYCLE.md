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
5. Tell each live page that it becomes hidden, so it can save its state.
   The next section describes this handoff.
6. Stop and release every live web view.
7. Remove notification observers.
8. Save the selected space and service, then ask `StoreRecoveryCoordinator` to
   record the store content.
9. Flush recent website storage, as described below.

### Visibility handoff at quit

During the life of the app, the visibility override script
(`UserScriptManager.makeVisibilityOverrideScript()`) makes each page read
visible and blocks each `visibilitychange` event. Many web apps save their
state when the page becomes hidden, because a browser sends that event before
a tab closes or the browser quits. With the override, a page never gets this
save point. WhatsApp Web kept its session after a quit and reopen in Safari,
but not in Paguro.

The maintainer confirmed the cause and the fix on hardware on September 24,
2026, with a Debug build on macOS 27. Before the handoff, a plain quit and
reopen signed WhatsApp out. With the handoff and the storage flush below,
WhatsApp stayed signed in across several `Command-Q` quits and reopens, with
content blocking on and off.

The script defines a release function with a long, non-enumerable name
(`UserScriptManager.visibilityReleaseFunctionName`). The function makes the
page read hidden, stops the block, and sends `visibilitychange` to the
document and `pagehide` (not persisted) to the window. The native side can
only call the main frame. So the function then calls the same function in each
same-origin child frame, and each child frame does the same for its own
children. A cross-origin frame blocks the access, so it does not get the
event.

Before the teardown, `AppState.shutdown()` calls `QuitVisibilityHandoff.run`:

- It calls the release function in every live web view, in parallel.
- It stops waiting after 300 ms, even if a page does not answer.
- When at least one page accepted the call, it waits at least 150 ms in
  total, because a save handler can start asynchronous IndexedDB writes.
- A page that throws or has no release function, such as an error page, does
  not count as accepted.
- It does not wait when no web view is live.

`QuitVisibilityHandoffPolicy` in PaguroCore holds the limits.
`BoundedParallelRace` runs the calls against a deadline, and the storage flush
uses the same type. The override stays on for the whole life of the app.
Hibernation does not use the handoff.

The deadline timer runs off the main actor. In an early version the timer ran
on the main actor, so a busy main thread delayed it three times. It delayed
the start of its sleep, its wake-up, and the return to the caller. On hardware, a
300 ms cap ended after 556 ms. Now the race decides at the deadline, and only
the return to the caller waits for the main thread. Nothing can shorten that
last wait, because AppKit must get its reply on the main thread.

Paguro writes one line at the notice level in the `WebView` category:

```text
Quit visibility handoff: views=<n> accepted=<n> timedOut=<bool> elapsedMs=<n>
```

When the main thread holds the return for 50 ms or more, a second line
follows:

```text
Quit visibility handoff delayed by the main thread: delayMs=<n>
```

### Website storage flush at quit

A test on macOS 27 found that a quick exit directly after the web-view
teardown can lose the last local storage writes of a page. Cookies and
IndexedDB kept their writes in the same runs, so the stores of one site did
not agree after the next launch. The flush protects the writes that the
visibility handoff starts.

Before the teardown, `WebViewPool.persistentDataStoresForQuitFlush()` collects
the persistent data store of each live web view, each store once. The pool
skips non-persistent stores, such as the stores of the first-run preview.
After the teardown, `AppState.shutdown()` calls `QuitStorageFlush.run`:

- It asks each store for its data records of all types, in parallel. In the
  test, this fetch waited for the pending writes. A cookie fetch did not.
- It stops waiting after 500 ms, even if a store does not answer.
- It waits at least 50 ms after the teardown, also when all stores answer
  sooner.
- It does not wait when no web view was live.

`QuitStorageFlushPolicy` in PaguroCore holds the limits and the store
selection. The flush reduces the risk of lost website storage at quit. It does
not guarantee that a site keeps its session.

Paguro writes one line at the notice level in the `DataStore` category:

```text
Quit storage flush: stores=<n> completed=<n> timedOut=<bool> elapsedMs=<n>
```

The 500 ms timeout starts when the fetches start. The elapsed time starts at
the teardown, so it also contains the steps between the teardown and the
fetches. When the main thread holds the return for 50 ms or more, a second
line follows:

```text
Quit storage flush delayed by the main thread: delayMs=<n>
```

### Exit paths

These exit paths go through `applicationShouldTerminate`, so they include the
flush:

- `Command-Q`, the Quit menu items, and the Dock Quit action.
- Logout, restart, and shutdown. macOS sends a quit Apple event, and AppKit
  accepts the `terminateLater` reply.
- Sparkle Install and Relaunch. The Sparkle installer sends a quit Apple event
  (`NSRunningApplication.terminate`) and waits for the process to exit.
- The relaunch after a store restore. `AppRelauncher.quit()` calls
  `NSApp.terminate`.

Paguro does not call `exit` and does not opt in to sudden or automatic
termination. A crash, a force quit, or a `SIGTERM` or `SIGKILL` signal ends the
process without the flush.

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
