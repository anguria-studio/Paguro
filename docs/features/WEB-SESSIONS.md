# Web sessions

Status: account isolation verified; service audit active

## Purpose

Blatta lets one user sign in to more than one account for a service.
The accounts must not share cookies or local storage.

## Identity

Each service account has a stable UUID.
The UUID identifies its `WKWebsiteDataStore`.

Blatta reuses one store object for each UUID during a process run.
WebKit keeps the store data on disk after the app quits.

## Isolation rule

One service account must not use another account data store.
This rule also applies to temporary badge probes.

Tests must create two accounts on the same origin.
The tests must prove that both sessions stay separate after a relaunch.

The automated application test writes a different cookie to each account store.
It rebuilds the data-store manager and reads both values again.
It then clears the first value and confirms that the second value remains.

The compatibility fixture uses local storage for the manual process test.
This test confirms that the values remain separate after `Command-Q` and a new launch.

The manual test passed on 2026-08-24.
Two services on the fixture origin kept different marker values after Blatta quit and started again.

## Public WebKit policy

Blatta uses public WebKit APIs only.
It does not disable Intelligent Tracking Prevention.

Some cross-site sign-in flows can fail with standard WebKit policy.
The service matrix must record this result.

Do not add a private selector to make one service pass.
Use an external sign-in route when a public route exists.
Otherwise mark the service as limited.

## User agent

Every service view uses the desktop Safari value from `UserAgentProvider` when
the service has no stored override. This avoids an app-specific token and lets
services provide the same web app that they provide to Safari.
Authentication popups inherit the opener value. External in-app browser
windows use the desktop default.

A catalog entry can supply a service-specific override when Blatta creates the
service. The Mobile view setting stores Blatta's Mobile Safari value as the
override. Turning Mobile view off clears that value and restores the desktop
Safari default. Changing this setting reloads a live view. A view created after
hibernation reads the current stored value.

Temporary badge views use the same service override or desktop default. Their
requests must match the service session that they inspect.

Before a release, update the Safari version token to a current shipping major.
Update the Mobile Safari tokens at the same time. Keep Safari's desktop
platform token unchanged, including on Apple silicon.

## Web-view pool

The pool owns each live `WKWebView` and coordinator.
Views must not create or retain a second pool.
The pool reports service activation and hibernation through lifecycle
callbacks. `HibernationScheduler` owns the hibernate, wake, and removal
callbacks and forwards notification-related events to `NotificationRuntime`.
`NotificationRuntime` owns the activation and navigation callbacks that start
or refresh polling. The content view does not start or stop pollers.

The pool can hibernate an inactive service.
It must first check these conditions:

- the service is not the active service;
- no active call;
- no active microphone, including a muted one;
- no active camera;
- policy permits hibernation.

A download does not block hibernation. Its download handler stays alive until
the transfer ends, and `Command-Q` cancels it.
Blatta does not track user interaction inside a page. The pool never hibernates
the active service, and it restarts the idle timer when the user selects a
service.

Wake must keep the same data-store identifier.
Wake must not present old unread state as a new message.
Wake resumes at the last `http` or `https` page. A service that showed the
error page when it hibernated resumes at its home URL.

## Navigation

`BlattaCore` classifies each navigation before it loads.
The coordinator converts WebKit values to the Core request and performs the result.
The result can stay in the service, open in another Blatta service, or open outside Blatta.

An unknown custom scheme opens only after an explicit rule accepts it.
Blatta must not pass an untrusted scheme to the system without review.

A web view loads only `http`, `https`, `about`, `blob`, and `data` URLs.
The coordinator cancels every other scheme before WebKit tries it.
A user click on an accepted scheme, such as `mailto:` or `tel:`, opens the
system handler. The coordinator drops a programmatic navigation to a non-web
scheme.
The in-app browser applies the same click rule.

A failed page load shows the error page with a retry action.
Three failures keep the current page instead.
They are a load that the user cancelled, a URL that WebKit cannot show, and a
load that WebKit interrupted to start a download.

## Popups

A service can request a new window.
Blatta can use an in-app browser panel for a required sign-in or task.

The popup must use the correct service data store.
It must not create a shared default data store.

An authentication popup can start after the service page redirects its opener
to a provider marketing host. Blatta accepts completion only after two checks.
The popup must start at a known authentication host. It must return to the live
opener host or the configured service host. If the opener leaves the configured
service, Blatta loads the service home instead of reloading the marketing page.
This rule keeps separate products on a shared provider domain isolated.

## Files

Uploads use a native open panel.

The sandbox compatibility test must verify uploads and downloads.
If direct download access fails, use a save panel and a security-scoped URL.

## Downloads

`WebViewCoordinator` sends a response to `WebDownloadHandler` in two cases.
The first case is an explicit `Content-Disposition: attachment` header.
The second case is a response that WebKit cannot show.
A navigation action that asks for a download follows the same route.

The handler saves each file in the user's Downloads folder.
The app has the `files.downloads.read-write` entitlement for this folder.
A name that already exists receives a numeric suffix before its extension.
The handler keeps itself alive until the transfer ends, so a download survives
hibernation of its service.
`Command-Q` cancels every download that is still running.
A stopped web content process also cancels its downloads.

`DownloadTracker` keeps the download records for the current app run.
It holds plain values, so it holds no WebKit object.
The handler reports the start, the byte counts, the destination, and the result.
It reads `WKDownload.progress` on a short main-actor tick instead of a key-value
observer. The observer delivers its values on an unspecified thread, and the
tick keeps every value on one actor.
The tick is 150 milliseconds, so the ring moves in small steps.

Records stay in memory. They reach no store, and the process drops them at
quit. The island's recent list uses the same model.
The tracker keeps the newest 25 records and drops the oldest ended one first.

`DownloadIndicatorState` in `BlattaCore` owns the visibility rules.
The app supplies the byte totals, the record count, the failed count, and the
running time of its oldest active download.
The state is therefore a pure function of its inputs. It reads no clock.
`DownloadTracker.state(for:now:)` is the one place that reads the clock.

The rules use one delay, `ringDelay`, of 500 milliseconds:

1. Without a record, the indicator hides.
2. With a download older than the delay, it shows the ring.
3. With a younger download and an earlier result, it keeps that result.
4. With a younger download and no earlier result, it hides.
5. Without a running download, it shows the resting or failed mark.

Rule 3 stops a new download from flashing a ring over a mark that the user
reads. Rule 4 keeps a fast download out of the header until it has something
to report.
A running download wins over a failed record, and the failure mark returns
when that download ends.

`Item.startedAt` supplies the elapsed value. The progress ticker runs for the
complete transfer, including the part before the delay, but it writes only
when a byte count changes. `DownloadTracker` therefore also starts one wake
task for each download, so a stalled transfer still shows its ring on time.

The badge counts new downloads, and the control counts records. `resolve`
therefore takes both `recordCount` and `unseenCount`. The first decides
whether the control appears, and the second decides the badge.

A record counts as unseen while it runs. After it ends, it counts until
`badgeWindow` of 12 seconds passes or the user opens the list. `Item.endedAt`
and `Item.acknowledged` hold those two facts, and `DownloadTracker` compares
them against the current time. One wake task for each result clears the badge
on time, in the same way as the ring-delay task.

`DownloadCountLabel` formats the badge. It follows the island counter rule
with a smaller cap, because the badge sits on a header control.
`DownloadIndicatorMotion` keeps the entry, arc, and pulse values, so the view
holds no timing of its own.

The state names its mark as a meaning instead of as artwork.
`Glyph.downloadMark` asks for the Blatta download asset.
`Glyph.systemSymbol` names one system symbol.
The package therefore needs no asset catalog and no interface framework.
The header view maps each value to a drawing.

A record leaves the list in three ways:

1. The user dismisses one ended record.
2. The user clears every ended record of the service.
3. The user stops a running download.

A stop withdraws the download, so it removes the record instead of leaving a
result. A dismiss therefore never applies to a running download, because its
row offers the stop action instead.

Showing a file in the Finder keeps its record. The complete row of a finished
download starts that action. Its dismiss control is a separate view beside
that row action, so one click reaches one control only.

Each header shows the downloads of its own service.
A sign-in popup uses the coordinator of the service that opened it, so its
downloads stay with that service.
A download without a service appears in every header. This rule keeps a
download visible when Blatta cannot name its source.

See [Native shell](NATIVE_SHELL.md) for the header control.

## Camera and microphone

The service asks through the WebKit UI delegate.
`MediaPermissionCoordinator` then applies the app and service policy.
It serializes native prompts and denies a pending request when its web view
closes or the application locks.

The system permission prompt remains the final authority.
Blatta must handle denial without a loop.

The File menu can mute microphones that are actively capturing audio.
Blatta disables the action when no microphone is active.
After the action, Blatta confirms the number of muted microphones and shows a
muted microphone mark on each affected service.
The service context menu can mute or unmute an engaged microphone.
This action does not block a future microphone request.

## Failure recovery

WebKit can stop a web content process.
The coordinator must cancel or reconcile active work.
The pool then creates a new view with the same service data store.

Do not remove a data store while a web view still uses it.
WebKit can crash during that operation.

## Data removal

The user can remove one service account.
Blatta first releases each related web view.
`WebsiteDataReclaimer` then records a durable tombstone, releases the cached
data-store handle, and retries removal through the public WebKit API.

The removal path must survive an interrupted app run.
It must not remove another service account's data.
Before removal, the reclaimer drops a tombstone when a live service claims the
identifier. It scans for unclaimed stores only after a healthy store launch.
It cancels delayed work during application shutdown. If shutdown cancels the
removal or WebKit rejects every attempt, the tombstone remains for the next launch.

## Compatibility matrix

Each supported service needs dated results for these functions:

- sign in and sign out;
- two-account isolation;
- session persistence;
- popup sign-in;
- unread state;
- notifications;
- click route;
- upload and download;
- camera and microphone;
- call protection;
- hibernation and wake;
- known cross-site sign-in limit.
