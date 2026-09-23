# Architecture

Status: active

## Purpose

Paguro is a native macOS shell for web services.
Each service runs in a separate `WKWebView` session.
Paguro owns the native window, service navigation, notifications, and island.

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
Paguro/
├── Paguro/                macOS application target
├── PaguroTests/           application and WebKit tests
├── Core/                  PaguroCore Swift package
├── docs/                  public project documents
├── scripts/               repeatable maintenance tools
├── .project/              private work plan, ignored by Git
└── project.yml            XcodeGen project source
```

## Dependency direction

`PaguroCore` must not import SwiftUI, AppKit, WebKit, or SwiftData.
The application target can import `PaguroCore`.
The application target owns all platform adapters.
The direct-release project adds Sparkle 2.9.6 to this target for signed updates.
The default project and PaguroCore do not depend on Sparkle.
PaguroCore owns the `AppDistribution` feature matrix. The app selects its
compiled distribution in `AppCapabilities`; build specifications and compiler
guards keep excluded dependencies and request code out of each edition.

```text
SwiftUI views
      ↓
App model and feature controllers
      ↓
Platform adapters     PaguroCore rules
      ↓                    ↑
AppKit, WebKit, SwiftData  pure values and policies
```

Do not let a view create a data store or web view directly.
Use the application model or a feature controller.

## Application composition

`PaguroApp` creates the SwiftUI scenes.
`AppModel` is the application composition root.
It creates each long-lived service one time.
`AppState.init` constructs the graph and loads saved values.
`AppDelegate` calls `AppState.start()` after AppKit finishes launching.

The main services and startup adapters are:

- `AppState` for application and feature state.
- `StoreLoader` for SwiftData migration, integrity checks, and launch recovery.
- `StoreRecoveryCoordinator` for recovery notices, backup selection, and restart handoff.
- `PreferencesStore` for the single loaded preferences row and typed commits.
- `WorkspaceStore` for workspace and service queries, mutations and selection persistence.
- `ServiceIconDraft` for cancellable icon previews in the add-service form.
- `LinkOpeningSettings` for the persisted global outside-link default.
  `PaguroCore.LinkOpeningPolicy` resolves each service override against it.
- `PasskeyNoticeController` for the app-wide explanation and its saved seen state.
- `ShellPreferences` for normalized window appearance and rail settings.
  `PaguroCore.ShellGlassStyle` defines presets and their fixed tint and frost values; the
  app maps each mode to native materials. `ShellGlassSupport` resolves platform
  fallbacks and available choices without rewriting saved preferences.
- `MediaPermissionCoordinator` for capture policy and native permission prompts.
- `DataStoreManager` for WebKit data stores.
- `WebsiteDataReclaimer` for durable, deferred removal of unused WebKit stores.
- `HibernationScheduler` for idle sweeps and immediate-hibernation grace tasks.
- `WebViewPool` for live and hibernated web views.
- `WebViewCoordinator` for navigation and UI delegate routing.
- `AuthPopupController` for popup windows and sign-in completion.
- `WebDialogPresenter` for file pickers and page dialogs.
- `WebDownloadHandler` for download lifetime, destinations, and cancellation.
- `DownloadTracker` for the global download list that the content header
  shows, with the source service on each record.
- `DownloadFlightState` for the marks that report a download start and land in
  the header control.
- `ErrorPage` for escaped local WebKit recovery pages.
- `NotificationManager` for WebKit badge polling and notification authorization.
- `NotificationPresenter` for validated native notification requests and delivery.
- `NotificationRuntime` for polling lifecycle, DND timing, unread badges, and click routing.
- `NotificationRouteSettings` for the enabled system and island presentation routes.
- `SystemScreenGeometryProvider` for current public `NSScreen` values.
- `IslandScreenChangeMonitor` for public display, window, Space, and wake events.
- `IslandPanelController` for optional island state, placement, and panel lifetime.
- `AppPresenceController` for Dock and menu-bar behavior.

`AppModel` connects island alert actions to the notification navigation path.
The island controller does not fetch or select service models directly.

The main rail and shared service catalog send model mutation intents to `AppState`.
`WorkspaceStore` owns their SwiftData queries, commits, and rollback.
`AppState` owns selection updates and post-save runtime work. Destructive
WebKit cleanup starts only after `WorkspaceStore` returns a saved outcome.
Settings views do not mutate `AppPreferences`. They send typed intents to the
application model. `PreferencesStore` saves each change before the application
model applies its runtime side effects.
`ShellPreferences` keeps the shell settings in one value. It preserves the
existing storage split: layout and appearance use `PreferencesStore`; glass,
icon-rail, and workspace-view settings use `UserDefaults`.
`NotificationRouteSettings` also uses `UserDefaults`. A route setting does not
change the SwiftData model or service account data.

`DataStoreManager` owns current account stores. `NotificationRuntime`,
`NotificationMessageHandler`, and `NotificationPresentationRouter` coordinate
current notification work. `NotificationEvent` and presentation policies live
in PaguroCore. `IslandPanelController` is optional. Proposed manager names in
older planning notes do not describe additional runtime components.

## App lifecycle

Paguro has one process in version 1.
It has no push server.
The direct build uses Sparkle installer helpers during an app update.
These helpers do not run service sessions or notification polling.

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

Each service account has a stable record ID and a separate
`dataStoreIdentifier` UUID. The data-store UUID identifies its persistent
`WKWebsiteDataStore`.
The data store keeps cookies and local storage separate from other accounts.

`WebViewPool` targets `WebViewPoolCapacity`, currently 15 live web views.
Above that number it releases eligible least recently used services, even when
idle hibernation is off. Active, messaging, pinned, and Keep Loaded services are
exempt. Protected views can keep the total above the target.
It can hibernate an inactive service when policy permits this action.
It must not hibernate a service during a call or while the camera or
microphone is in use.
It must not hibernate a service that keeps playing audio either.
`HibernationGate` in `PaguroCore` holds that rule, and the
idle sweep, the capacity sweep, and the immediate policy all read it, so one
guard covers every route. A download continues after hibernation, because the
download handler keeps itself alive until the transfer ends.
The pool reports service activation and hibernation through callbacks.
`HibernationScheduler` owns the hibernate, wake, and removal callbacks and
forwards notification-related events to `NotificationRuntime`. It also owns the
capacity notice, because it already reads the service record that names the
released service.
`NotificationRuntime` owns the pool callbacks that start active or background
badge polling. SwiftUI views do not start or stop polling.

`WebViewCoordinator` handles navigation, redirects, external links, media
requests, and web process failure. It forwards component-specific work:

- `AuthPopupController` owns each sign-in popup and its dependent child windows.
  Page-owned close callbacks preserve the opener so its session handoff can finish;
- `WebDialogPresenter` owns upload pickers and page dialogs;
- `WebDownloadHandler` owns downloads after navigation handoff and reports
  each one to `DownloadTracker`;
- `ErrorPage` builds local failure and crash recovery pages.

It converts navigation actions to `NavigationRequestContext` values.
`PaguroCore` owns the deterministic navigation decision and its routing order.

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
`PaguroCore`. Core validates the frame origin and decodes a bounded
`NotificationPayload`. The handler then applies the app policy and posts the
macOS notification.
`NotificationRuntime` coordinates live and transient badge polling, manual and
scheduled Do Not Disturb, sleep and network suspension, and safe click routing.
It also supplies effective service mute to `WebViewPool`. The pool uses the
Core `MediaPlaybackPolicy` to combine mute with background suspension and
applies the result through public WebKit media playback controls. A call and a
service that plays audio each cancel the background reason; mute wins over both.
`BackgroundAudioExemptions` in `PaguroCore` holds the life cycle of the audio
exemption, and the pool owns the poll timer and the WebKit playback calls.
The bundled `WebAudioMuteScript` also silences Web Audio contexts created
after suspension, including those in child frames. The web view configuration
installs that script, so the first document of a service already holds it.
`NotificationMessageHandler` validates and normalizes the page signal into
`PaguroCore.NotificationEvent`. `NotificationPresentationRouter` applies the
shared policy before sending it to the system or island presenter.

The island does not detect notifications.
`AppState` synchronously forwards lock changes to the notification manager and
the island through a callback installed by `AppModel`. The manager owns a
thread-safe lock snapshot shared by page routers, native presenters, and the
notification delegate. Core presentation policy suppresses both routes when
locked. The island also rejects direct previews while locked.
It only presents events from the notification pipeline.
`NotificationIslandTiming` keeps its deterministic alert times in `PaguroCore`.
The panel controller owns the cancellable transition schedule.

See [Notification system](features/NOTIFICATIONS.md).

## Data ownership

SwiftData stores Paguro settings, spaces, service records, and links.
WebKit stores service cookies, caches, and local storage.

`PreferencesStore` loads or creates one `AppPreferences` row. It is the only
type that writes that row.
`WorkspaceStore` is the SwiftData facade for spaces, services, links,
favicons, page zoom, and window selection. `PasskeyNoticeController` saves the
app-wide seen state in UserDefaults. Existing per-service seen fields remain
for schema compatibility and seed the app-wide value during migration.

The Debug first-run preview uses an in-memory model container and one
nonpersistent WebKit store per account. It bypasses normal-store recovery and
persistent session enumeration. Its shell settings use isolated defaults that
reset on each launch, with glass Off. The normal app keeps persistent account
stores and its saved preferences.

Paguro must not store account passwords.
Paguro must not copy full message history into its data store.
Paguro must not persist notification bodies by default.

## Configuration transfer

PaguroCore owns the versioned JSON schema and complete-file validation.
WorkspaceStore imports fresh accounts and workspace links in one transaction,
with PreferencesStore staging portable preference fields. Replacement deletes
old records in that transaction; session cleanup follows the successful save.
AppModel applies
runtime changes only after the save. ShellPreferences maps its portable values.
Native file panels and bounded file reads stay in the app target. Export never
reads WebKit storage. See [Configuration transfer](features/CONFIGURATION.md).

## Concurrency

The project uses Swift 6 strict concurrency.
UI state and WebKit objects stay on the main actor.
Pure values in `PaguroCore` conform to `Sendable` where possible.

Background work must return immutable results to the main actor.
Do not send a WebKit object across actors.

## Security boundaries

The app uses App Sandbox and Hardened Runtime.
It requests only the entitlements that a current feature needs.

The page bridge accepts a small data message.
It must not provide a general native command channel.
Subframe messages must have an approved origin.
Each string and URL must have a size and format limit.

Paguro does not use private WebKit selectors.
Paguro does not disable Intelligent Tracking Prevention.

## Project generation

XcodeGen creates `Paguro.xcodeproj` from `project.yml`.
Do not edit the generated project by hand.

Git ignores the generated project. Generate it locally or in CI from the
selected specification. `project-direct.yml` and `project-store.yml` add the
edition-specific release settings.

## Test layers

`PaguroCoreTests` test pure values and policies.
`PaguroTests` test application services and WebKit adapters.
Native view tests use AppKit hosts and simulated screen geometry. Debug preview
schemes support manual onboarding, island, and notification checks.

The local HTTPS fixture exercises notifications, frames, downloads, media, and
session persistence. Live service results remain dated evidence in the private
service matrix, not a guarantee of provider compatibility.

See [Compatibility fixture](features/COMPATIBILITY.md).

## Change rule

Update this document when a module boundary or dependency direction changes.
Record a large decision in `docs/decisions/` when the reason needs a permanent record.
