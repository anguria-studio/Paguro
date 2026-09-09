# Compatibility fixture

Status: ready for manual WebKit checks

## Purpose

The compatibility fixture is a local HTTPS service.
It exercises the public WebKit paths that Blatta depends on.

The fixture provides these controls:

- page and service worker notification calls;
- document title unread counts;
- same-origin and cross-origin frames;
- a pop-up window;
- file upload and download;
- camera and microphone capture;
- a loopback WebRTC call;
- a persistent session marker;
- a simulated WebKit process failure.

## Safety boundary

The server listens only on `127.0.0.1`.
It creates a temporary self-signed certificate each time it starts.
The run script removes the certificate and key when it stops.
It does not add a certificate to the system trust store.

The `Blatta Compatibility` scheme uses the `Compatibility` build configuration.
This configuration uses the `com.tommasolaterza.Blatta.compatibility` bundle ID
and adds the `--blatta-compatibility-fixture` argument.
It is a debug build, so it can use the fixture argument.
Blatta then accepts the temporary certificate on ports 8443 and 8444 only.

A Release build cannot enable this behavior.

Notification tests need a signed Compatibility build.
An ad-hoc signed app can load the fixture, but macOS rejects its notification request.
Follow the local signing steps in `CONTRIBUTING.md` before you test notifications.

The separate bundle ID keeps fixture permissions and data out of the normal
Debug app. It also gives notification authorization tests a stable identity.

## Start the fixture

Run this command from the repository root:

```sh
scripts/run_compatibility_fixture.sh
```

The command starts these origins:

- primary: `https://localhost:8443`;
- secondary: `https://127.0.0.1:8444`.

Keep the command running during the test.

In a second terminal, run this command:

```sh
scripts/capture_compatibility_logs.sh
```

The command saves the latest native trace in
`.project/logs/compatibility-latest.log`.
The `.project` directory is private and Git ignores it.

## Open the fixture in Blatta

1. Run `xcodegen generate`.
2. Select the `Blatta Compatibility` scheme in Xcode.
3. Run Blatta.
4. Add a custom service named `Blatta Fixture`.
5. Set its URL to `https://localhost:8443`.
6. Open the service.

Do not open the fixture in the normal Blatta scheme.
The normal scheme does not accept its temporary certificate.

## Manual checklist

| Check | Expected result |
|---|---|
| Page notification | Blatta receives one native notification request |
| Service worker notification | Blatta receives the page call through the worker registration |
| Delayed notification | Blatta receives the event after 10 seconds unless the app quits |
| Title badge | The service unread count follows the document title |
| Same-origin frame | Blatta accepts the frame notification |
| Cross-origin frame | Blatta rejects the frame notification |
| Pop-up | Blatta opens a separate window that shares the service session |
| Upload | A native file panel opens and the fixture reports the received bytes |
| Download | Blatta saves `blatta-fixture.txt` in Downloads |
| Camera | Blatta asks for permission and shows the local preview when allowed |
| Microphone | Blatta asks for permission and starts an audio track when allowed |
| Loopback call | WebRTC connects and Blatta marks the service as call-active |
| Session marker | The marker remains after a Blatta relaunch |
| Process failure | Blatta calls its recovery path and reloads the fixture |

Record each result in the service matrix or the related backlog item.

## Test two accounts on one origin

Use two Blatta services for this test.
The URL query labels each fixture page.
It does not change the web origin.

1. Add a custom service named `Fixture account A`.
2. Set its URL to `https://localhost:8443/?account=A`.
3. Add a custom service named `Fixture account B`.
4. Set its URL to `https://localhost:8443/?account=B`.
5. Store `account-a` in account A.
6. Store `account-b` in account B.
7. Use `Command-Q` to quit Blatta.
8. Start Blatta with the `Blatta Compatibility` scheme again.
9. Open both fixture accounts.
10. Confirm that each page shows only its own stored marker.
11. Clear the marker in account A.
12. Confirm that account B still shows `account-b`.

The fixture reads the marker when the page loads.
You do not have to select **Read marker** after the new launch.

The diagnostic report contains the fixture account label and a marker-present flag.
It does not contain the marker value.

## Read the diagnostic trace

A macOS banner is only the final presentation step.
macOS can group banners or delay their visual presentation.
Do not use the number of visible banners as the event count.

The fixture log records the control click and the page result.
The native log records these later stages:

- Blatta accepted or rejected the frame;
- the service policy accepted or suppressed the event;
- the notification center accepted or rejected the request;
- the foreground delegate asked for a banner and sound;
- the title badge value changed;
- the media permission delegate allowed or denied a request.

Each native notification request has a short trace identifier.
Use it to follow one request through the native stages.

The title badge poll runs at an interval.
The visible badge can take up to five seconds to change while the service is active.
Notification events do not increment the unread count.
The page title or the service DOM is the unread count source.
This rule prevents duplicate alerts from increasing a badge that the service cannot clear.

Select **Prepare diagnostic report** after a test.
The page selects a JSON report that you can copy with Command-C.
The report contains page state and fixture events.
It does not contain cookies, page content, or the session marker.

The page reports `Notification.permission` as `granted` because Blatta supplies the
page notification bridge.
This value does not describe the macOS notification permission.
Use the native `center settings authorization` value for the macOS state.

For a microphone test, start the microphone and speak.
The level meter must move when WebKit receives an audio signal.
For a WebRTC test, use headphones and start the loopback call.
The call state must become `connected`.

## Stop the fixture

Press Control-C in the fixture terminal.
The server stops both origins and removes its temporary TLS files.

## Automated checks

Run the fixture server tests with this command:

```sh
scripts/test_compatibility_fixture.sh
```

The tests check static route safety, the required controls, uploads, downloads, and both request methods.
The application tests check the Debug launch boundary and loopback certificate policy.
They also use two identifier-based data stores for one cookie origin.
The test rebuilds the manager, reads both values, clears one value, and checks the other value.

## Limits

The service worker control calls `showNotification` from the page.
It does not emulate a push event that runs only inside a worker.

WebKit has no public API that terminates a content process for a test.
The failure control calls Blatta's normal recovery handler in a Debug build.
It does not kill a real WebKit process.

Apple silicon Mac laptops and Intel Mac laptops with a T2 chip disconnect the
built-in microphone when the lid closes.
Use an external microphone for a closed-lid media test.
