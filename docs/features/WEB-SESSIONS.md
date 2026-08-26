# Web sessions

Status: account isolation verified; service audit active

## Purpose

Atoll lets one user sign in to more than one account for a service.
The accounts must not share cookies or local storage.

## Identity

Each service account has a stable UUID.
The UUID identifies its `WKWebsiteDataStore`.

Atoll reuses one store object for each UUID during a process run.
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
Two services on the fixture origin kept different marker values after Atoll quit and started again.

## Public WebKit policy

Atoll uses public WebKit APIs only.
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

A catalog entry can supply a service-specific override when Atoll creates the
service. The Mobile view setting stores Atoll's Mobile Safari value as the
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
Atoll does not track user interaction inside a page. The pool never hibernates
the active service, and it restarts the idle timer when the user selects a
service.

Wake must keep the same data-store identifier.
Wake must not present old unread state as a new message.
Wake resumes at the last `http` or `https` page. A service that showed the
error page when it hibernated resumes at its home URL.

## Navigation

`AtollCore` classifies each navigation before it loads.
The coordinator converts WebKit values to the Core request and performs the result.
The result can stay in the service, open in another Atoll service, or open outside Atoll.

An unknown custom scheme opens only after an explicit rule accepts it.
Atoll must not pass an untrusted scheme to the system without review.

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
Atoll can use an in-app browser panel for a required sign-in or task.

The popup must use the correct service data store.
It must not create a shared default data store.

An authentication popup can start after the service page redirects its opener
to a provider marketing host. Atoll accepts completion only after two checks.
The popup must start at a known authentication host. It must return to the live
opener host or the configured service host. If the opener leaves the configured
service, Atoll loads the service home instead of reloading the marketing page.
This rule keeps separate products on a shared provider domain isolated.

## Files

Uploads use a native open panel.
Downloads currently target the Downloads folder.

The sandbox compatibility test must verify both actions.
If direct download access fails, use a save panel and a security-scoped URL.

## Camera and microphone

The service asks through the WebKit UI delegate.
`MediaPermissionCoordinator` then applies the app and service policy.
It serializes native prompts and denies a pending request when its web view
closes or the application locks.

The system permission prompt remains the final authority.
Atoll must handle denial without a loop.

The File menu can mute microphones that are actively capturing audio.
Atoll disables the action when no microphone is active.
After the action, Atoll confirms the number of muted microphones and shows a
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
Atoll first releases each related web view.
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
