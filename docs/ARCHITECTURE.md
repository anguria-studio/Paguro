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

The main services are:

- `AppState` for application and feature state.
- `PreferencesStore` for the single loaded preferences row and typed commits.
- `DataStoreManager` for WebKit data stores.
- `WebViewPool` for live and hibernated web views.
- `WebViewCoordinator` for WebKit delegates.
- `NotificationManager` for notification polling and macOS delivery.
- `AppPresenceController` for Dock and menu-bar behavior.

The main rail and service-add sheets send model mutation intents to `AppState`.
`AppState` owns their SwiftData commits, rollback, selection updates, and
post-save runtime work.
Settings views do not mutate `AppPreferences`. They send typed intents to the
application model. `PreferencesStore` saves each change before the application
model applies its runtime side effects.

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
coordinator keeps the download alive until it ends.
The pool reports service activation and hibernation to `AppState`.
`AppState` starts active or background badge polling from those lifecycle
events. SwiftUI views do not start or stop notification polling.

`WebViewCoordinator` handles these WebKit operations:

- navigation and redirects;
- new windows and external links;
- uploads and downloads;
- camera and microphone requests;
- page dialogs;
- web process failure;
- notification bridge messages.

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
