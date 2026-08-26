# Notification system

Status: planned

## Purpose

Atoll must show useful events from web services.
It must work without an official API for each service.

No single web signal works for all services.
Atoll therefore uses a small set of signal sources.

## Current runtime ownership

`NotificationRuntime` owns manual and scheduled Do Not Disturb, badge-polling
lifecycle, sleep and network suspension, and notification or menu-bar click
routing. `NotificationManager` owns WebKit badge polling and notification
authorization. `NotificationPresenter` builds and delivers native notification
requests after the page bridge validates their payloads. Detection and
presentation remain separate from this lifecycle controller.

## Signal sources

### Page notifications

Atoll can wrap the page `Notification` constructor.
It can also wrap page calls to `showNotification`.

This source can provide a title, body, tag, icon, and target URL.
It is the best generic source for an individual event.

A service worker can create a notification outside the page context.
Atoll cannot always see that event.

### Document title and badge

Atoll can observe the document title.
It can also run a small badge query for an audited service.

This source usually provides an unread count.
It does not always identify a new message.

### Service recipe

Atoll bundles each recipe as a small rule for one service.
Use a recipe only when generic signals are not sufficient.

Each recipe needs these items:

- a named owner;
- a test fixture;
- a service version note;
- a clear removal path;
- a documented data scope.

Atoll must not download executable recipes at run time.

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

`AtollCore` owns this value type.

## Validation

The bridge must check each message before use.

1. Confirm that Atoll has an active service account.
2. Confirm that Atoll permits the frame origin.
3. Reject an unknown message type.
4. Limit the byte count for each string.
5. Remove control characters that have no display use.
6. Parse the URL without loading it.
7. Apply the service route policy to the URL.

Atoll must approve an origin before a subframe sends a message.
The first implementation should require the main origin.

The bridge must not expose file access, shell access, or a general native command.

The current bridge limits each UTF-8 field before presentation. A title can use
512 bytes, and a body can use 4,096 bytes. An icon URL can use 2,048 bytes. A
tag can use 512 bytes, and a service ID can use 64 bytes. The decoder removes
control characters that have no display use. It keeps tabs and line breaks.

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

Policy code belongs in `AtollCore` when it does not need a platform API.

## Presentation

Atoll supports two presentation routes:

- the Atoll island;
- `UNUserNotificationCenter`.

These routes use the same event.
The app must not run two detection systems.

The default must avoid two visible alerts for one event.
The user can enable both routes when desired.

macOS always uses the Atoll app icon as the sender identity for a native
notification. Public notification APIs do not let Atoll replace that icon for
each service.

Atoll adds the service icon as an image attachment when an icon is available.
Each notification receives its own copy of the icon file, because macOS moves
an attachment file into the notification store.
It also adds the service name as the notification subtitle. macOS controls the
size and location of the attached image.

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

The route policy must reject these values:

- a non-HTTP scheme unless Atoll has a specific handler;
- a host that the service does not own;
- a URL with invalid syntax;
- a URL that exceeds the size limit.

When no safe URL exists, Atoll opens the service root.

## Background behavior

An active web view can produce page events.
A hibernated web view cannot provide the same live behavior.

A lightweight badge probe can update unread state for some services.
It must use the same service data store.
It must not create a second account session.

When Atoll starts, it first records an unread baseline.
It must not present old unread items as new alerts.

When the user quits Atoll, all notification work stops.
Version 1 has no push server and no helper process.

## Privacy

Atoll does not persist notification bodies by default.
The island keeps only the events that it needs for its current state.

Logs must not contain a message body, token, cookie, or full private URL.
Diagnostic output can contain a service ID and a redacted host.

## Known limits

- A service-worker-only event can be invisible to Atoll.
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
