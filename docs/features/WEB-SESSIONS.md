# Web sessions

Status: inherited and under audit

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

## Public WebKit policy

Atoll uses public WebKit APIs only.
It does not disable Intelligent Tracking Prevention.

Some cross-site sign-in flows can fail with standard WebKit policy.
The service matrix must record this result.

Do not add a private selector to make one service pass.
Use an external sign-in route when a public route exists.
Otherwise mark the service as limited.

## Web-view pool

The pool owns each live `WKWebView` and coordinator.
Views must not create or retain a second pool.

The pool can hibernate an inactive service.
It must first check these conditions:

- no active call;
- no active microphone;
- no active camera;
- no active download;
- no current user interaction;
- policy permits hibernation.

Wake must keep the same data-store identifier.
Wake must not present old unread state as a new message.

## Navigation

The coordinator classifies each navigation before it loads.
The result can stay in the service, open in another Atoll service, or open outside Atoll.

An unknown custom scheme opens only after an explicit rule accepts it.
Atoll must not pass an untrusted scheme to the system without review.

## Popups

A service can request a new window.
Atoll can use an in-app browser panel for a required sign-in or task.

The popup must use the correct service data store.
It must not create a shared default data store.

## Files

Uploads use a native open panel.
Downloads currently target the Downloads folder.

The sandbox compatibility test must verify both actions.
If direct download access fails, use a save panel and a security-scoped URL.

## Camera and microphone

The service asks through the WebKit UI delegate.
Atoll then applies its app and service policy.

The system permission prompt remains the final authority.
Atoll must handle denial without a loop.

## Failure recovery

WebKit can stop a web content process.
The coordinator must cancel or reconcile active work.
The pool then creates a new view with the same service data store.

Do not remove a data store while a web view still uses it.
WebKit can crash during that operation.

## Data removal

The user can remove one service account.
Atoll first releases each related web view.
It then removes the persistent data store.

The removal path must survive an interrupted app run.
It must not remove another service account data.

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
