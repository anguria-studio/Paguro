# Browser extensions

Status: opt-in prototype for issue [#199](https://github.com/anguria-studio/Paguro/issues/199).

Paguro can run Firefox extensions inside the services you choose. Each service
account gets its own copy of the extension, with its own storage and sign-ins.
The engine is still WebKit. An extension can load fine and still fail when it
needs a browser feature that WebKit or Paguro does not provide.

## Turn it on

The prototype needs macOS 15.4 or later. It is off by default.

- Development and direct-download builds: launch with `--paguro-browser-extensions`.
- For development, run the **Paguro Extensions Prototype** scheme. It uses a
  separate bundle identifier and sandbox, so your normal accounts stay untouched.
  Set up signing as described in [Contributing](../../CONTRIBUTING.md).
- The App Store build leaves out the downloader, the runtime, and the controls.

## Install an extension

1. Open Settings > Extensions.
2. Paste a Firefox Add-ons link and select Review extension.
3. Check the name, version, and the access it asks for.
4. Pick the services that should get it, then select Install in selected services.

Review only downloads and checks the package. Nothing runs until you install.
Installation grants the access the extension requires, but only in the services
you picked. A broad website pattern never reaches a service you left out.

To change services later, use Choose services in Settings, or Manage extensions
for this service in Edit service. Changes save first, then Paguro rebuilds only
the affected service views. Calls and active media block a change, because the
rebuild would interrupt them. Save your work first, since a reload can lose
unsaved page state.

## Use an extension

When the active service has extensions, a puzzle button appears before
Downloads, Back, and Forward. Its menu lists each extension. Choose one to run
its action or open its popup. Extensions with an options page get a Settings
entry too.

The popup has a Keep open checkbox and a Close button. Keep open lets you work
in the page and come back to the extension without losing what you typed.
Switching service, locking Paguro, or quitting always closes the popup.

An extension can open a page, such as a new tab or its options page. Paguro
shows it in a separate window labeled with the extension and service. It uses
the same account, never a shared browser session. Each service can have up to
four of these windows.

## Optional access

Some extensions ask for extra access later. Paguro shows a native sheet that
names the extension, the service, and exactly what it wants:

- **Allow** saves the access for this extension in this service only.
- **Deny** remembers the refusal, so the extension cannot keep asking.
- **Cancel** changes nothing. It is the default.

Requests only work from the active service, right after you use the extension.
Native messaging to desktop apps is always denied. Settings has Reset extra
access to clear these choices. A new package version clears them too.

## Compatibility profile

Some extensions decide what to do from the browser name. In Manage extensions
for this service you can pick a profile:

- **Standard** keeps the service's normal browser identity.
- **Firefox** reports a Firefox identity to the extension and the service page.
  It overrides Mobile view and a custom user agent while it is selected.

This changes only the reported name. It does not add Firefox APIs. The
Firefox version number is fixed in `ExtensionRuntimeProfile`. Raise it as
Firefox releases move on, because some sites warn about old browsers.

## Updates and removal

Paguro checks Firefox Add-ons for newer versions once a day. A check reads
public metadata only. When an update is available, Settings shows Review
update and the puzzle button shows a blue dot. Nothing installs until you
approve the new review.

Remove asks first, then unloads the extension and deletes its package. WebKit
can keep some extension storage, and website sign-ins are not touched.

If the saved extension library cannot be read, Paguro leaves the file alone
and Settings offers Reset extension library. Reset keeps a copy of the
unreadable file, removes the saved packages, and starts empty.

## Diagnostics

WebKit can report runtime errors from an extension. Paguro never blocks the
extension because of them. An orange dot on the puzzle button means the active
service has diagnostics. The extension's menu and Settings show the details.
An error does not prove the extension is broken, and no errors does not prove
it works.

## How it works

The pure rules live in PaguroCore: link parsing, archive checks, page URL rules,
the saved library schema, optional access, profiles, and update policy.

The app target owns the WebKit and AppKit parts:

- `FirefoxAddonClient` reads Mozilla's public API and downloads packages.
- `BrowserExtensionManager` owns the library, reviews, assignments, and updates.
- `ServiceExtensionSession` owns one `WKWebExtensionController` per live service.
  The controller and its extension views use that service's own data store.
  Never let it fall back to WebKit's shared default store.
- `BrowserExtensionPageController` owns each extension page window.
- `WebViewPool` attaches the controller before it creates the service view.

At launch, Paguro reads the saved assignments before the first service view
exists, so every assigned service gets its controller right away. Saved
packages are checked again and then attached to the open views. WebKit injects
content scripts into pages that are already open, so launch does not reload
any service.

A fully hibernated service has no extension running. Command-Q cancels
downloads, closes popups and pages, and unloads every extension.

## Safety rules

- Only `https://addons.mozilla.org` listing links can select a package.
  Downloads must come from Mozilla hosts over HTTPS.
- The package must match Mozilla's size and SHA-256. This checks integrity,
  not Mozilla's signature or the extension's behavior.
- The archive check rejects encrypted files, links, unsafe paths, duplicate
  names, and overlapping entries. Limits: 64 MiB download, 256 MiB expanded,
  8,192 entries.
- A package with manifest errors is never installed.
- An extension page window shows HTTP, HTTPS, the extension's own files, or
  `about:blank`. Frames inside it can also use `blob:`, `data:`, and
  `about:srcdoc`, which options pages often build with. Script and file
  addresses are always blocked.
- No private WebKit API, hidden browser, or remote scripts.

One small compatibility shim exists. `BrowserExtensionAPICompatibility` adds
the standard `scripting.ExecutionWorld` constants in extension documents when
WebKit already provides `scripting.executeScript` but not the constants. It
grants nothing and adds no API that WebKit withholds. It does not reach
service-worker backgrounds.

## Known limits

- Desktop native messaging is not supported, so password-manager desktop
  connections do not work.
- No context menus, browser windows, or full tabs model.
- No Chrome Web Store or Safari extension installation.
- Each selected service runs its own extension background, so memory grows
  with every service you add. See the next section.

## Memory cost

Every service keeps its own copy of an extension, so nothing is shared between
services. The cost grows in a straight line with the number of services:

| Extension | Extra memory per service |
| --- | --- |
| Bitwarden 2026.10.0 | about 105 MiB |
| Dark Reader 4.9.134 | about 35 MiB |
| Simple Translate 3.1.0 | about 17 MiB |

So Bitwarden in 10 services costs about 1 GB. Dark Reader in 10 services
costs about 350 MB. These figures come from 5 and 10 throwaway services on a
16 GB Apple silicon Mac with macOS 27.2, on 29 October 2026. Bitwarden was
signed out, and the pages were small synthetic ones, so real use costs more.
A hibernated service frees its copy.

This is the price of keeping accounts separate, and it is why the installer
asks you to pick services instead of installing everywhere. A heavy extension
belongs in the few services that need it.

To measure again, run:

```sh
scripts/measure_extension_memory.py
```

It downloads the public packages, opens throwaway accounts in the test host,
and measures only the processes each phase starts, with `footprint`. The Debug
test host also runs the services saved in its own store, and their processes
come and go. Runs with one service are therefore noisy; trust 5 and 10.

See [Extension compatibility](EXTENSION-COMPATIBILITY.md) for how we test real
extensions and what we found.

## Verify

Start small:

```sh
swift test --package-path Core --filter 'FirefoxAddonSourceTests|ExtensionArchivePolicyTests'
xcodegen generate
xcodebuild -project Paguro.xcodeproj -scheme Paguro -configuration Debug \
  -only-testing:PaguroTests/BrowserExtensionTests test
```

Popup focus tests need Paguro to be the active app. If macOS keeps another
app in front, they skip with a message instead of failing. Run them again
with nothing else in use to cover them.

The normal suite uses synthetic extensions and no network downloads. The
**Paguro Extension Compatibility** scheme opts into live downloads of real
packages.

## API references

- [Apple: WKWebExtension](https://developer.apple.com/documentation/webkit/wkwebextension)
- [Apple: WKWebExtensionControllerDelegate](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate)
- [Apple: controller default website data store](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/configuration-swift.class/defaultwebsitedatastore)
- [Mozilla add-on API](https://mozilla.github.io/addons-server/topics/api/addons.html)
