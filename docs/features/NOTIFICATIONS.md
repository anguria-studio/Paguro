# Notification system

Status: in progress

## Purpose

Blatta must show useful events from web services.
It must work without an official API for each service.

No single web signal works for all services.
Blatta therefore uses a small set of signal sources.

## Current runtime ownership

`NotificationRuntime` owns manual and scheduled Do Not Disturb, badge-polling
lifecycle, sleep and network suspension, and notification or menu-bar click
routing. `NotificationManager` owns WebKit badge polling and notification
authorization. `NotificationPresenter` builds and delivers native notification
requests after the page bridge validates their payloads. Detection and
presentation remain separate from this lifecycle controller.

## Signal sources

### Page notifications

Blatta can wrap the page `Notification` constructor.
It can also wrap page calls to `showNotification`.

The current source provides a title, body, and tag.
It is the best generic source for an individual event.

A service worker can create a notification outside the page context.
Blatta cannot always see that event.

### Document title and badge

Blatta can observe the document title.
It can also run a small badge query for an audited service.

This source usually provides an unread count.
It does not always identify a new message.

### The badge expression

The service catalog entry can carry a `badgeJS` field. The field holds one
JavaScript expression that reads the unread count of that service from its own
page. `ServiceCatalog` loads the field from
`Blatta/Resources/ServiceCatalog.json`.

An entry with a `badgeJS` field makes that expression the only badge source for
the service. Blatta never reads the title of such a service. A title count
belongs to another view of the page, such as a different Gmail label or the
global LinkedIn count. A fallback to the title would therefore report the
wrong number. An entry without the field uses the title.

The expression runs in the page through `evaluateJavaScript`. It must read the
page only. It must not write to the page, follow a link, or reach the network.

`BadgeCountExtractor.readJSResult` reads the returned value. WebKit bridges
every JavaScript number to an `NSNumber` that holds a double, so the rule
accepts a whole-valued double. Element text can hold a group separator or a
"more than" marker, so `"1,234"` reads as 1234, `"9+"` reads as 9, and `" 3 "`
reads as 3. Empty text reads as zero.

An expression that cannot read its page must return `null`. A `null` result
means "no count", and it keeps the current badge. A result of `0` is an
authoritative empty state, and it clears the badge.

`BadgeManager` limits every count to the range 0 to 999. A page cannot corrupt
the Dock total with a negative or huge value.

Each expression needs a test in `WebRuntimeTests` that runs it against a page
shaped like the real DOM.

### Service recipe

Blatta bundles each recipe as a small rule for one service.
Use a recipe only when generic signals are not sufficient.

Each recipe needs these items:

- a named owner;
- a test fixture;
- a service version note;
- a clear removal path;
- a documented data scope.

Blatta must not download executable recipes at run time.

## Event model

The page bridge sends an untrusted signal.
The app validates the signal before it creates `NotificationEvent`.

The event contains these values:

- event ID;
- service account ID;
- signal source;
- title;
- optional body;
- optional tag;
- optional target URL;
- receipt time.

`BlattaCore` owns this value type.

The current page bridge creates this event before it applies presentation
policy. Normalization trims display text, changes empty body and tag values to
`nil`, and removes a body that repeats the title. A signal with an empty title
does not create an event.

## Validation

The bridge must check each message before use.

1. Confirm that Blatta has an active service account.
2. Confirm that Blatta permits the frame origin.
3. Reject an unknown message type.
4. Limit the byte count for each string.
5. Remove control characters that have no display use.
6. Parse the URL without loading it.
7. Apply the service route policy to the URL.

Blatta accepts a main-frame signal. It also accepts a subframe signal when its
origin is the same as the main-frame origin. It rejects a cross-origin signal.

The bridge must not expose file access, shell access, or a general native command.

The current signal uses schema version `1` and type `web-notification`. The
complete UTF-8 message can use 16,384 bytes. A title can use 512 bytes, a body
can use 4,096 bytes, and a tag can use 512 bytes. The decoder rejects another
version or type. It removes control characters that have no display use. It
keeps tabs and line breaks.

The page does not send a service ID or notification icon. The native message
handler binds each signal to its service account. Native presentation uses the
known service icon. Extra page fields cannot replace these values.

## Policy pipeline

The pipeline applies rules in this order:

1. Validate the event.
2. Normalize empty and repeated fields.
3. Find a deduplication key.
4. Reject a recent duplicate.
5. Apply the per-service mute rule.
6. Apply global Do Not Disturb.
7. Apply quiet time.
8. Select the allowed presentation routes.
9. Save a short-lived routing record.
10. Present the event.

Policy code belongs in `BlattaCore` when it does not need a platform API.

The current duplicate key contains the service account ID, tag, title, and
body. It does not contain the event ID, receipt time, detector source, or target
URL. This lets two detectors identify the same event. A changed title or body
remains a new event even when the service reuses a tag.

Blatta rejects an equal key for five seconds. The in-memory set keeps at most
256 keys and removes the oldest key first. Blatta does not persist this set or a
notification body.

## Presentation

Blatta supports two presentation routes:

- the Blatta island;
- `UNUserNotificationCenter`.

These routes use the same event.
The app must not run two detection systems.

The default must avoid two visible alerts for one event.
The user can enable both routes when desired.

`NotificationPresentationRouter` now applies mute, Do Not Disturb, and route
settings once for both destinations. `BlattaCore` returns a deterministic route
plan. The default plan selects only the system notification route. The page
message handler no longer calls a platform presenter directly.

Settings has separate controls for macOS notifications and island alerts.
The island control appears only when a connected display has a camera housing.
The island document gives that rule and its debug override.
The system route is on by default. The island route is off by default.
The user can turn on either route, both routes, or neither route. These local
route choices use `UserDefaults` and do not change service session data.

The global system-route control applies before each per-service macOS control.
A service produces a macOS notification only when both controls are on.

The island route requires a camera housing on the selected display.
When the display has no camera housing, an enabled island route falls back to
one macOS notification. The fallback does not create a duplicate when the
system route is also on.

The island destination is optional in the router. It stays unavailable until
Blatta installs an island presenter and selects a notched display.

Clicking an island alert uses the same service-account navigation path as a
macOS notification. The island does not create a second service-selection path.

The island removes the events of one service account when the user reads that
conversation. The selection of that service account and an unread count of zero
start this rule. The island document gives the rule in full.

macOS always uses the Blatta app icon as the sender identity for a native
notification. Public notification APIs do not let Blatta replace that icon for
each service.

Blatta adds the service icon as an image attachment when an icon is available.
Each notification receives its own copy of the icon file, because macOS moves
an attachment file into the notification store.
It also adds the service name as the notification subtitle. macOS controls the
size and location of the attached image.

## macOS permission

Both presentation routes need the macOS notification permission. The island
falls back to a macOS notification on a display without a notch, so a missing
permission hides that route too. macOS also gates the Dock badge through this
permission, so a missing permission empties the Dock badge as well.

### When Blatta asks

`NotificationRuntime.start()` owns the request. It runs from
`applicationDidFinishLaunching`, one turn later, for every launch.

The request does not belong to a view. The root view never appears for a login
item launch, which closes the main window, and it never appears in "Menu bar
only" mode. A request in that view can therefore miss every such launch.

`NotificationRuntime` installs the notification delegate at the same moment.
The first touch of `UNUserNotificationCenter` binds the process to the
notification service. A touch during `App.init` happens before AppKit finishes
the launch, so `NotificationManager.init` must not make it.

Blatta reads the permission first and then applies
`NotificationAuthorizationPolicy.shouldRequest`. A fresh install reads
`notDetermined`, so Blatta asks and macOS shows its prompt.

### A refusal and a failure are different

Two states look the same from outside. In both, no banner appears and
`notificationSettings()` reports `denied`:

- the user refused the permission;
- macOS never registered Blatta and refused the request.

The permission alone cannot separate them, so Blatta uses the request outcome:

- macOS **returns** whenever it could run the request, with `granted` true or
  false. The reported permission then holds the answer of the user.
- macOS **throws** only when it could not run the request. It asked nobody, so
  the reported `denied` describes the platform and not the user.

A thrown request gives the state `unavailable`. A completed request gives the
reported permission, which can be `authorized`, `denied`, or `provisional`.

### The retry rule

macOS remembers a refusal. It remembers no failure. Blatta therefore asks once
at each launch unless macOS already permits the notification, and a launch that
reads `denied` still asks.

That request costs the user nothing: macOS answers a request under a stored
refusal from that stored decision and shows no prompt. It is also the only way
to separate the two states, because both report `denied` at launch.

Blatta asks one time for each launch, never again after an activation. A failed
request fails for a reason that no activation changes.

Blatta reads the permission again at each activation, because the user changes
it in System Settings. `NotificationAuthorizationPolicy.merge` keeps
`unavailable` while macOS keeps reporting `denied`, and it accepts `authorized`
or `provisional` at once. Without that rule the first activation would show the
user a refusal that they never made.

### The Settings warning

A permission that delivers nothing is silent without help. Blatta still builds
each notification, and `UNUserNotificationCenter` still accepts each request.
macOS then drops the banner and reports nothing to the app.

`NotificationManager` therefore keeps an observable permission value. Settings
shows a warning row above the Presentation section when that value is not
`authorized`. The row names the problem and opens the System Settings
notification pane:

```
x-apple.systempreferences:com.apple.preference.notifications
```

Each state has its own words. A `denied` state asks the user to turn the
permission on. An `unavailable` state explains that macOS never asked, and it
gives the remedy: move Blatta to the Applications folder and open it once from
there. macOS registers the app at that point and asks for the permission. An
app that macOS never registered does not appear in the notification pane at
all, so the pane alone cannot fix it.

The app maps `UNAuthorizationStatus` to `NotificationAuthorizationState` at the
platform boundary. `BlattaCore` holds that enum, the state machine, and the
warning text, and it imports no AppKit or UserNotifications type.

Use this command to read the current permission from the log:

```sh
log stream --predicate 'subsystem == "com.tommasolaterza.Blatta"' --info
```

## Dock badge

The Dock icon shows the total unread count of all service accounts.
The Settings switch "Show badge count on Dock icon" controls this badge.
A new install has the switch on.

`BadgeManager` keeps one unread count for each service account.
It adds the counts of the service accounts that show a badge.
A muted service account adds nothing.
A service account with its own badge switch off also adds nothing.

`DockBadgePolicy` in `BlattaCore` makes the label from the total and the
Settings switch.
The Dock shows the label at a total of one or more.
The Dock shows no badge at a total of zero.
Do Not Disturb keeps the badge, because Do Not Disturb stops banners only.

The Dock icon must be present for the badge.
The Settings picker "Show Blatta in" controls the Dock icon.
In "Menu bar only" mode the Dock icon goes away after the last window closes,
so the Dock can show no badge in that mode.

`BadgeManager` writes one log line for each change of the badge.
Use this command to read the current state:

```sh
log stream --predicate 'subsystem == "com.tommasolaterza.Blatta"' --info
```

## Global mute

The content header has one global notification mute beside reload.
It applies to all spaces and services.
The same state is available in Settings and through `Shift-Command-D`.

Global mute suppresses new macOS notification banners. Unread counts remain
visible in service badges, workspace totals, and the Dock badge. Each visible
workspace header and service adds a barred bell while manual global mute is
active.

Global mute does not delete notifications that macOS has already delivered.
It does not stop web views or sign services out.

## Workspace mute

The workspace context menu can mute every service in that workspace. The mute
hides badges and suppresses new macOS notification banners. It preserves each
service's raw unread count, so unmuting restores the badges immediately.

If several workspaces share a service, muting any of them also mutes the
service.

## Click routing

A click first selects the service account.
It then loads the approved target URL when one exists.

A click also shows the main window. Blatta activates the application and orders
that window forward, or asks SwiftUI to build the window again when the user
closed it. The selection happens first, so the window shows the right service
account as it appears. A click on a service account that no longer exists
changes no selection and shows no window.

The route policy must reject these values:

- a non-HTTP scheme unless Blatta has a specific handler;
- a host that the service does not own;
- a URL with invalid syntax;
- a URL that exceeds the size limit.

When no safe URL exists, Blatta opens the service root.

## Background behavior

An active web view can produce page events.
A hibernated web view cannot provide the same live behavior.

A lightweight badge probe can update unread state for some services.
It must use the same service data store.
It must not create a second account session.

When Blatta starts, it first records an unread baseline.
It must not present old unread items as new alerts.

When the user quits Blatta, all notification work stops.
Version 1 has no push server and no helper process.

## Privacy

Blatta does not persist notification bodies by default.
The island keeps only the events that it needs for its current state.

Logs must not contain a message body, token, cookie, or full private URL.
Diagnostic output can contain a service ID and a redacted host.

## Known limits

- A service-worker-only event can be invisible to Blatta.
- A title badge can show unread state without a new-event boundary.
- A service page change can break a recipe.
- Exact conversation routing is not always available.
- A hibernated service cannot promise instant events.

The service matrix must state these limits for each service.

## Tests

The local fixture must cover these cases:

- a page notification;
- a page `showNotification` call;
- a title count change;
- a repeated tag;
- a burst of equal events;
- a same-origin frame;
- a hostile cross-origin frame;
- a valid target URL;
- an invalid scheme;
- an over-size title or body;
- a click after the main window closes;
- a relaunch with an old unread count;
- a quit before a delayed signal.

Unit tests must cover each policy branch.
Integration tests must verify the bridge and native delivery.
