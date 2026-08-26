# Architecture

Status: active

## Purpose

Atoll is a native macOS shell for web services.
Each service runs in a separate `WKWebView` session.
Atoll owns the native window, service navigation, notifications, and island.

## System rules

1. Use public Apple APIs only.
2. Keep each service account in a separate data store.
3. Treat all web content as untrusted input.
4. Keep notification detection separate from presentation.
5. Stop all work when the app quits.
6. Keep pure rules outside AppKit and WebKit.
7. Keep feature limits visible in the documentation.

## Repository map

```text
Atoll/
├── Atoll/                 macOS application target
├── AtollTests/            application and WebKit tests
├── Core/                  AtollCore Swift package
├── docs/                  public project documents
├── scripts/               repeatable maintenance tools
├── .project/              private work plan, ignored by Git
└── project.yml            XcodeGen project source
```

## Dependency direction

`AtollCore` must not import SwiftUI, AppKit, WebKit, or SwiftData.
The application target can import `AtollCore`.
The application target owns all platform adapters.

```text
SwiftUI views
      ↓
App model and feature controllers
      ↓
Platform adapters     AtollCore rules
      ↓                    ↑
AppKit, WebKit, SwiftData  pure values and policies
```

Do not let a view create a data store or web view directly.
Use the application model or a feature controller.

## Application composition

`AtollApp` creates the SwiftUI scenes.
`AppModel` is the application composition root.
It creates each long-lived service one time.
`AppState.init` constructs the graph and loads saved values.
`AppDelegate` calls `AppState.start()` after AppKit finishes launching.

The main services and startup adapters are:

- `AppState` for application and feature state.
- `StoreLoader` for SwiftData migration, integrity checks, and launch recovery.
- `StoreRecoveryCoordinator` for recovery notices, backup selection, and restart handoff.
- `PreferencesStore` for the single loaded preferences row and typed commits.
- `WorkspaceStore` for workspace and service queries, mutations, seeding, and selection persistence.
- `ShellPreferences` for normalized window appearance and rail settings.
- `MediaPermissionCoordinator` for capture policy and native permission prompts.
- `DataStoreManager` for WebKit data stores.
- `WebsiteDataReclaimer` for durable, deferred removal of unused WebKit stores.
- `HibernationScheduler` for idle sweeps and immediate-hibernation grace tasks.
- `WebViewPool` for live and hibernated web views.
- `WebViewCoordinator` for navigation and UI delegate routing.
- `AuthPopupController` for popup windows and sign-in completion.
- `WebDialogPresenter` for file pickers and page dialogs.
- `WebDownloadHandler` for download lifetime, destinations, and cancellation.
- `ErrorPage` for escaped local WebKit recovery pages.
- `NotificationManager` for WebKit badge polling and notification authorization.
- `NotificationPresenter` for validated native notification requests and delivery.
- `NotificationRuntime` for polling lifecycle, DND timing, unread badges, and click routing.
- `AppPresenceController` for Dock and menu-bar behavior.

The main rail and service-add sheets send model mutation intents to `AppState`.
`WorkspaceStore` owns their SwiftData queries, commits, and rollback.
`AppState` owns selection updates and post-save runtime work. Destructive
WebKit cleanup starts only after `WorkspaceStore` returns a saved outcome.
Settings views do not mutate `AppPreferences`. They send typed intents to the
application model. `PreferencesStore` saves each change before the application
model applies its runtime side effects.
`ShellPreferences` keeps the shell settings in one value. It preserves the
existing storage split: layout and appearance use `PreferencesStore`; glass,
icon-rail, and workspace-view settings use `UserDefaults`.

The planned `SessionStoreManager` and `NotificationPipeline` will replace the
current managers when their runtime phases start. The planned `IslandStore`
and `IslandPanelController` will remain optional services. The backlog tracks
these changes.

## App lifecycle

Atoll has one process in version 1.
It has no helper process and no push server.

Closing the main window keeps the menu-bar item active.
Configured services can continue to produce notifications.

`Command-Q` stops the process.
It also stops every web view, timer, and notification source.

A login launch starts in accessory mode unless the user keeps the Dock icon visible.
The app enters regular mode when it shows a main window.
It returns to accessory mode after the last main window closes unless the user
keeps the Dock icon visible.

`AppDelegate` delays AppKit termination while `AppModel` stops timers,
notification sources, network monitors, and web views and saves final state.
See [Application lifecycle](features/APP-LIFECYCLE.md).

## Web runtime

Each service account has a stable UUID.
That UUID identifies a persistent `WKWebsiteDataStore`.
The data store keeps cookies and local storage separate from other accounts.

`WebViewPool` limits the number of live web views.
It can hibernate an inactive service when policy permits this action.
It must not hibernate a service during a call or while the camera or
microphone is in use. A download continues after hibernation, because the
download handler keeps itself alive until the transfer ends.
The pool reports service activation and hibernation through callbacks.
`HibernationScheduler` owns the hibernate, wake, and removal callbacks and
forwards notification-related events to `NotificationRuntime`.
`NotificationRuntime` owns the pool callbacks that start active or background
badge polling. SwiftUI views do not start or stop polling.

`WebViewCoordinator` handles navigation, redirects, external links, media
requests, and web process failure. It forwards component-specific work:

- `AuthPopupController` owns new-window and sign-in popup lifecycle;
- `WebDialogPresenter` owns upload pickers and page dialogs;
- `WebDownloadHandler` owns downloads after navigation handoff;
- `ErrorPage` builds local failure and crash recovery pages.

It converts navigation actions to `NavigationRequestContext` values.
`AtollCore` owns the deterministic navigation decision and its routing order.

See [Web sessions](features/WEB-SESSIONS.md).
See [Web appearance](features/WEB-APPEARANCE.md).
See [Service icons](features/SERVICE-ICONS.md).

## Notification flow

```text
web signal
    ↓
origin and payload validation
    ↓
mute, notify-OS, and Do Not Disturb policy
    ↓
macOS notification delivery
    ↓
safe click route to the service
```

The WebKit bridge adapter sends normalized origins and the raw payload to
`AtollCore`. Core validates the frame origin and decodes a bounded
`NotificationPayload`. The handler then applies the app policy and posts the
macOS notification.
`NotificationRuntime` coordinates live and transient badge polling, manual and
scheduled Do Not Disturb, sleep and network suspension, and safe click routing.
The backlog tracks the split of that handler into detection and presentation
parts, and a shared event type in `AtollCore` for the island.

The island does not detect notifications.
It only presents events from the notification pipeline.

See [Notification system](features/NOTIFICATIONS.md).

## Data ownership

SwiftData stores Atoll settings, spaces, service records, and links.
WebKit stores service cookies, caches, and local storage.

`PreferencesStore` loads or creates one `AppPreferences` row. It is the only
type that writes that row.
`WorkspaceStore` is the SwiftData facade for spaces, services, links, default
seeding, passkey-notice state, favicons, page zoom, and window selection.

Atoll must not store account passwords.
Atoll must not copy full message history into its data store.
Atoll must not persist notification bodies by default.

## Concurrency

The project uses Swift 6 strict concurrency.
UI state and WebKit objects stay on the main actor.
Pure values in `AtollCore` conform to `Sendable` where possible.

Background work must return immutable results to the main actor.
Do not send a WebKit object across actors.

## Security boundaries

The app uses App Sandbox and Hardened Runtime.
It requests only the entitlements that a current feature needs.

The page bridge accepts a small data message.
It must not provide a general native command channel.
Subframe messages must have an approved origin.
Each string and URL must have a size and format limit.

Atoll does not use private WebKit selectors.
Atoll does not disable Intelligent Tracking Prevention.

## Project generation

XcodeGen creates `Atoll.xcodeproj` from `project.yml`.
Do not edit the generated project by hand.

The repository tracks the generated project only when the project policy requires it.
The current setup generates it during local work.

## Test layers

`AtollCoreTests` test pure values and policies.
`AtollTests` test application services and WebKit adapters.
UI tests will use launch arguments and simulated screen geometry.

A local web fixture will test notifications, frames, downloads, and media requests.
Live service tests will use a documented compatibility matrix.

See [Compatibility fixture](features/COMPATIBILITY.md).

## Change rule

Update this document when a module boundary or dependency direction changes.
Record a large decision in `docs/decisions/` when the reason needs a permanent record.
