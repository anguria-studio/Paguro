# Web sessions

Status: account isolation verified; service audit active

## Purpose

Paguro lets one user sign in to more than one account for a service.
The accounts must not share cookies or local storage.

## Identity

Each service account has a stable record ID and a separate persisted
`dataStoreIdentifier` UUID. The latter identifies its `WKWebsiteDataStore`.

Paguro reuses one store object for each data-store UUID during a process run.
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
Two services on the fixture origin kept different marker values after Paguro quit and started again.

## Public WebKit policy

Paguro uses public WebKit APIs only.
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

A catalog entry can supply a service-specific override when Paguro creates the
service. The Mobile view setting stores Paguro's Mobile Safari value as the
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

The pool keeps a limited number of live web views. `WebViewPoolCapacity` in
`PaguroCore` holds that number, which is 15 at this time. The number is
provisional until a memory measurement confirms it.

This limit is separate from idle hibernation. Above the limit, the pool
releases the least recently used services, even when the user turns idle
hibernation off. The same exemptions apply: the active service, a pinned
service, a service with the "Keep Loaded" policy, and a chat app stay
live. The "Chat app setting" section of `NOTIFICATIONS.md` defines a chat app.

The first release of an app run shows a floating notice card above the web
content. The card names the service, states the number of services that stay
loaded, and points to "Keep Loaded". Later releases in the same app run show no
card, because they repeat one rule. `CapacityEvictionNotice` in `PaguroCore`
holds the rule, the title, and the text, and it builds the number from
`WebViewPoolCapacity.maxLoaded`. Performance settings state the same number from
the same source. `HibernationScheduler` owns the once-for-each-run flag and the
task that removes the notice after 12 seconds. `WebContentView` presents the
card. `docs/DESIGN.md` holds the shape, placement, and motion rules.

The pool can hibernate an inactive service.
It must first check these conditions:

- the service is not the active service;
- no active call;
- no active microphone, including a muted one that the page still holds;
- no active camera;
- no background audio exemption;
- policy permits hibernation.

`HibernationGate` in `PaguroCore` holds the deterministic part of that
decision. It reads one `HibernationFacts` value and returns the reason that
blocks the release, so a log line and a test name the same reason. The pool
keeps the WebKit state and the JavaScript call probe, because those are not
deterministic values.

Both sweeps read that one rule, so the same service is safe from both:

- the idle sweep, which releases a service after its idle threshold;
- the capacity sweep, which releases the least recently used services above
  the pool limit.

A call therefore blocks a capacity release as well. The capacity sweep does not
stop at a protected service. It takes the next eligible candidate instead.
If too few services are eligible, the pool can remain above its target. A call blocks the immediate policy as well, because
the grace task ends in the same shared decision.

A service that keeps playing audio holds the same kind of protection. Music and
a voice message therefore survive the capacity sweep and the idle sweep. The
audio reason is the last one in the list, so a call on the same service is still
the reason the log line reports.

The camera and microphone state comes from public WebKit properties, which no
test process can drive. The pool has one internal seam for each answer it cannot
compute. These are the capture state, the call probe, the playback state, the
audibility probe, and the clock of the audio grace period. A test sets the facts that a real device
and a real page would report. Production behavior does not change, because the pool
runs its own probe when no test replaces it.

A download does not block hibernation. Its download handler stays alive until
the transfer ends, and `Command-Q` cancels it. The header download list is
global, so it keeps reporting that transfer while the service sleeps.
Paguro does not track user interaction inside a page. The pool never hibernates
the active service, and it restarts the idle timer when the user selects a
service.

Wake must keep the same data-store identifier.
Wake must not present old unread state as a new message.
Wake resumes at the last `http` or `https` page. A service that showed the
error page when it hibernated resumes at its home URL.

## Media playback mute

`NotificationRuntime` supplies current global, quiet-hours, workspace, and
service mute to `WebViewPool`. The pool combines mute with its separate soft
hibernation state through `MediaPlaybackPolicy` in `PaguroCore`.
It applies public `setAllMediaPlaybackSuspended` before the first page load
and whenever either suspension reason changes. Activating a muted service
clears only soft hibernation. Clearing mute does not wake a background view.

A page that holds the camera or the microphone is in a call. Background
suspension must not silence the far end while the user reads another service,
so capture cancels the background reason. An explicit mute still wins, because
the user asked for silence. A call that starts or ends on a background service
changes this answer at once. The exception needs a local device, so a call that
only receives audio and video still follows the background rule.

### Background audio exemption

A service that plays audible media at the moment it leaves the screen keeps
playing. Music and a voice message that plays through a media element therefore
survive a switch to another service.

Two conditions must hold, at the switch and on each poll:

1. public `requestMediaPlaybackState` reports playing;
2. the audibility probe finds at least one audible media element.

The public state alone is not enough. It reports playing for a muted video as
well, and WhatsApp Web and Telegram Web keep muted looping videos for stickers,
avatars, and animated images. Those two services therefore held the mark, the
sound, and the protection from both hibernation sweeps on every switch, with
nothing audible.

The probe is a bounded, read-only JavaScript call that the pool starts, like the
call probe. It is not a page-to-native message, and it adds nothing to the
bridge. It returns two counts: how many media elements the page holds, and how
many of them are audible. An element counts as audible when it plays, has data
to play, and is not muted. Its volume must be above zero, and it must carry
sound. An `<audio>` element carries sound by definition. A `<video>` answers
through what WebKit exposes to the page: the decoded audio bytes first, then the
audio track list. An unmuted video that plays counts as audible when the page
reports neither of them.

A page can play a voice message or an alert sound through `new Audio()`, which
never enters the document, so `document.querySelectorAll('audio,video')` alone
would miss it. A bundled script wraps `HTMLMediaElement.prototype.play` at
document start, in every frame, and records each element that the page plays.
Listeners for `pause`, `ended`, and `emptied` remove the element again, so a
finished element can be collected. The script calls the original `play` and
returns its result unchanged. The probe reads the registry and the document
together, and it reads same-origin frames as well.

Each of these answers counts as not audible:

- a failed probe;
- a missing registry;
- a result of another shape;
- a probe that does not answer inside its bound.

A page that cannot answer therefore earns no exemption.

The pool asks the page at the switch, before suspension applies. Suspension
applied in that short window and lifted again would cut the sound. The pool
therefore treats the open question as playback and settles it one step later.

One log line at debug level reports each switch-time decision: the public state,
the audibility answer, and both counts. It holds no address, no title, and no
media source.

Playback that starts after the switch earns nothing. A background page must not
be able to keep itself awake by autoplay, so only the answer at the switch can
create the exemption.

`BackgroundAudioExemptions` in `PaguroCore` holds the life cycle: it grants at
the switch, refreshes on each poll, and expires after the grace period. It reads
one answer, so the pool combines the public state and the probe before it asks.
The
grace period is 90 seconds. It has to cover the gap between two tracks and a
short pause. The user can pause and resume with the keyboard media keys without
bringing Paguro forward. The pool polls each exempt service every 5
seconds. It polls no other service, so an ordinary background service costs
nothing.

The exemption ends for one of these reasons:

- the service returns to the screen;
- the user uses Pause Audio;
- mute applies;
- Paguro removes the service;
- the page has not reported audible playback for the grace period.

The normal background suspension applies again at that moment. `Command-Q` cancels the poll with the
rest of the pool work.

Known limits, with public APIs only:

- Sound that a page produces without a media element that Paguro can see does
  not keep the service playing after a switch. A WhatsApp Web voice message is
  the known case. The page decodes the sound itself and plays it where no public
  read reaches it. The probe therefore finds no element, not even a detached one.
  A running Web Audio context is no proof of sound either, because many web apps
  keep one context running in silence. Counting it would return Paguro to the
  reported fault.
- Media inside a cross-origin frame is not seen. That frame denies every read
  from the page, so neither its registry nor its elements can be reached.
- An unmuted element that plays pure silence counts as audible. No public API
  reports the current loudness of an element.

Mute wins over the exemption. Global, workspace, scheduled, and service mute
each silence the service and end the exemption. Clearing mute does not restore
it, which matches the rule that clearing mute does not wake a background view.

`docs/features/NATIVE_SHELL.md` holds the speaker mark and the Pause Audio
action.
New and rebuilt views read the current mute state, including quiet hours
before deferred notification startup completes.

`WebAudioMuteScript` closes a public WebKit suspension gap: a newly created
Web Audio context can start while suspension is active. The bundled script
routes connections to each live context's destination through an output gain.
Mute sets the gain to zero. It preserves the connection return value and
disconnection overloads, and it does not change offline rendering. Weak gain
references avoid retaining closed or unused contexts. Live updates propagate
from parent to child frames. New documents receive the current state at
document start. This is a generic compatibility guard, not a service recipe.

Paguro installs the guard with the web view configuration, so every document of
a service holds it from its first line. A later mute change writes the new value
two ways. It replaces that one copy, for the documents that load next. It also
tells the live document directly. It never adds a second copy, and it cannot
give the guard to a document that loaded without it.

Microphone capture remains under the separate capture controls.

## Navigation

`PaguroCore` classifies each navigation before it loads.
The coordinator converts WebKit values to the Core request and performs the result.
The result can stay in the service, open in another Paguro service, or open outside Paguro.

Settings > General > Web Content provides the Open outside links in Paguro
default, initially off. The service editor offers Follow global setting,
In Paguro, and In default browser. A service without an override follows the
current global value. Existing explicit choices remain overrides. Changes apply
to the next link click without reloading the service.

Links that match a configured service still switch to that service first.
Only unmatched HTTP and HTTPS links use the chosen browser destination.

The same route applies to a new-window request from a service, including
`window.open`, when the target host is outside the service. WebKit does not
ask the navigation check about `window.open`, so the coordinator applies
`WebRoutingPolicy.shouldRouteNewWindowExternally` before it creates a popup.
Some requests still open a Paguro popup. These are a known sign-in host, a
request that sets a window size (a probable sign-in popup), and a request from
a popup. A request with no HTTP or HTTPS host, such as `about:blank`, also
opens a popup.
`LinkOpeningPolicy` in PaguroCore resolves inheritance. `LinkOpeningSettings`
persists the global value in the launch-specific UserDefaults domain.

An unknown custom scheme opens only after an explicit rule accepts it.
Paguro must not pass an untrusted scheme to the system without review.

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
Once an interrupted load stops, its loading ring clears. A replacement load
keeps the ring, and stopping does not clear an existing failure mark.
The header Reload action and Command-R share one retry path. If WebKit has no
committed page to reload, retry the service home URL in the same account view.

## Popups

A service can request a new window.
Paguro can use an in-app browser panel for a required sign-in or task.

The popup must use the correct service data store.
It must not create a shared default data store.

When a popup opens another popup, keep its opener window alive. The child uses
the configuration supplied by WebKit, including the same account data store.
Closing a parent closes its dependent child windows. Closing a child leaves its
parent open and does not reload it.

A popup that closes itself owns the sign-in handoff to its opener. Paguro must
not reload that opener: a queued message or asynchronous session request can
still be pending. Keep the page alive so it can finish that request.

An authentication popup can start after the service page redirects its opener
to a provider marketing host. Paguro accepts completion only after two checks.
The popup must start at a known authentication host. It must return to the live
opener host or the configured service host. If the opener leaves the configured
service, Paguro loads the service home instead of reloading the marketing page.
This rule keeps separate products on a shared provider domain isolated.
This automatic return rule applies to the popup opened by the service, not to
child popups inside the authentication flow.

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
There is one download center for the whole app, so every query in it answers the
downloads of every service. It holds plain values, so it holds no WebKit object.
The handler reports the start, the byte counts, the destination, and the result.
It reads `WKDownload.progress` on a short main-actor tick instead of a key-value
observer. The observer delivers its values on an unspecified thread, and the
tick keeps every value on one actor.
The tick is 150 milliseconds, so the ring moves in small steps.

Records stay in memory. They reach no store, and the process drops them at
quit. The island's recent list uses the same model.
The tracker targets 25 records and drops the oldest ended records first.
It retains running transfers even when they exceed that limit.

`DownloadIndicatorState` in `PaguroCore` owns the visibility rules.
The app supplies the byte totals, the record count, the failed count, and the
running time of its oldest active download.
The state is therefore a pure function of its inputs. It reads no clock.
`DownloadTracker.state(now:)` is the one place that reads the clock.

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
`Glyph.downloadMark` asks for the Paguro download asset.
`Glyph.systemSymbol` names one system symbol.
The package therefore needs no asset catalog and no interface framework.
The header view maps each value to a drawing.

A record leaves the list in three ways:

1. The user dismisses one ended record.
2. The user clears every ended record.
3. The user stops a running download.

A stop withdraws the download, so it removes the record instead of leaving a
result. A dismiss therefore never applies to a running download, because its
row offers the stop action instead.

Showing a file in the Finder keeps its record. The complete row of a finished
download starts that action. Its dismiss control is a separate view beside
that row action, so one click reaches one control only.

The header shows the downloads of every service, and each record names the
service that started it. `Item.serviceID` holds that service, and
`Item.serviceLabel` holds its name as a snapshot from the moment the download
began. The snapshot keeps a record readable after the user renames or deletes the
service, and `AppState` supplies the name, so the tracker reads no store.
`DownloadSource` in `PaguroCore` turns the two values into what one row shows.

A sign-in popup uses the coordinator of the service that opened it, so its
downloads stay with that service.
A download without a service shows no source. This keeps the record visible when
Paguro cannot name its source, and it invents no source for it.

A download continues after its service hibernates, so the list keeps reporting
its progress while nothing shows that service's page. A capacity eviction and a
deletion of the service leave the record in place for the same reason. The
handler owns the transfer, and the record owns the name it captured.

See [Native shell](NATIVE_SHELL.md) for the header control.

## Camera and microphone

The service asks through the WebKit UI delegate.
`MediaPermissionCoordinator` then applies the app and service policy.
It serializes native prompts and denies a pending request when its web view
closes or the application locks.

The system permission prompt remains the final authority.
Paguro must handle denial without a loop.

The File menu can mute microphones that are actively capturing audio.
Paguro disables the action when no microphone is active.
After the action, Paguro confirms the number of muted microphones and shows a
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
Paguro first releases each related web view.
`WebsiteDataReclaimer` then records a durable tombstone, releases the cached
data-store handle, and retries removal through the public WebKit API.

The removal path must survive an interrupted app run.
It must not remove another service account's data.
Before removal, the reclaimer drops a tombstone when a live service claims the
identifier. It scans for unclaimed stores only after a healthy store launch.
It cancels delayed work during application shutdown. If shutdown cancels the
removal or WebKit rejects every attempt, the tombstone remains for the next launch.

## Investigating a lost sign-in

Distinguish a normal process restart from an app update, a cleared session,
a removed account, and a configuration import. Imports create fresh account
identifiers. Removing the final workspace link or clearing a session removes
website data by design. A normal restart or update must keep the same account
store identifier.

Record the Paguro version and build, macOS version and build, distribution
channel, service, and approximate time. For a QR-linked service, check whether
the provider still lists the Mac as a linked device. A missing provider entry
alone does not establish whether local storage or server-side pairing failed.

Compare normal quit and reopen with the update path. Use the isolated update
test in [Distribution](DISTRIBUTION.md#verify-an-update-privately) for synthetic
cookies and website database markers. Do not copy a real account's session into
test builds. A passing synthetic test does not rule out provider-specific issues.

A service that keeps its session in Safari but not in Paguro points to
something that Paguro adds. The visibility override caused the WhatsApp Web
sign-outs after quit and reopen. It blocked the hidden event that many web
apps use to save their state. At quit, Paguro now sends that event
first. The maintainer confirmed the fix on hardware on September 24, 2026,
with a Debug build on macOS 27. A new sign-out after quit with `accepted`
above zero in the handoff line points to another cause.

Paguro writes these lines at the notice level, so `log show` can read them
after the event. They contain only fixed reason strings, counts, Booleans, and
durations. They never contain a service name, URL, or page title.

| Category | Line | When |
| --- | --- | --- |
| `WebView` | `Quit visibility handoff: views=<n> accepted=<n> timedOut=<bool> elapsedMs=<n>` | Each quit, before the teardown. See [App lifecycle](APP-LIFECYCLE.md#visibility-handoff-at-quit). |
| `DataStore` | `Quit storage flush: stores=<n> completed=<n> timedOut=<bool> elapsedMs=<n>` | Each quit. See [App lifecycle](APP-LIFECYCLE.md#website-storage-flush-at-quit). |
| `WebView`, `DataStore` | `Quit visibility handoff delayed by the main thread: delayMs=<n>`, `Quit storage flush delayed by the main thread: delayMs=<n>` | A busy main thread held the quit for 50 ms or more after the step ended. |
| `WebView` | `Chat app web view torn down: reason=<reason> isChatApp=true` | Paguro releases a chat app web view for a reason other than quit: `idleHibernation`, `capacityEviction`, `manualHibernation`, `rebuild`, or `removal`. |
| `WebView` | `Chat app navigation started by Paguro: reason=<reason> isChatApp=true` | Paguro starts a main-frame load or reload in a chat app. `AppInitiatedNavigationReason` in PaguroCore lists the reasons, for example `initialLoad`, `wakeFromHibernation`, `crashRecoveryReload`, and `errorPageRetry`. |

Read them for the last day with this command:

```sh
/usr/bin/log show --last 1d --info --predicate 'subsystem == "studio.anguria.paguro" && (eventMessage BEGINSWITH "Quit " || eventMessage BEGINSWITH "Chat app")'
```

`scripts/capture_service_test_logs.sh` captures future WebView events while the
problem is reproduced. It cannot recover logs from an earlier incident. Review
its output before sharing, and never add cookies, tokens, or message content
to a report. Avoid deleting the account as a diagnostic step because it removes
the session being investigated.

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
