# Extension compatibility

Status: development workflow for issue [#199](https://github.com/anguria-studio/Paguro/issues/199).

A Firefox extension can install cleanly in Paguro and still fail at runtime.
This page explains how we test real extensions, how we record results, and
where things stand today. Dated measurements and package hashes live in the
issue, not here.

## Record results by operation

"It works" is too vague. Record the highest level you actually saw, with the
package version:

| Level | What you saw |
| --- | --- |
| Package accepted | Valid archive and manifest, permission review shown |
| Background starts | Background runs, storage works, messages get replies |
| Popup starts | The popup renders and responds |
| Operation works | One action completes with the expected result |
| Account flow works | Login, lock, autofill, and restart with a disposable account |

When something fails, name the likely cause:

- **Paguro integration:** a delegate, window, or host contract is missing.
- **WebKit capability:** the API is absent after permissions are confirmed.
- **Permission policy:** Paguro denies it on purpose.
- **Extension assumption:** the extension picks a path that does not fit here,
  for example from browser detection.
- **Unresolved:** it fails and we do not know why yet.

An error in the console does not mean the extension is broken. Change one
thing at a time.

## Ground rules for fixes

Fixes must help every eligible extension, not one vendor:

- Use public Apple APIs and keep each account's store and permissions intact.
- Add a synthetic regression test that does not need a vendor package.
- Never select a fix by extension name, ID, package hash, or error text.
- Never rewrite vendor scripts or hide errors to make something look working.
- If WebKit does not provide an operation, it stays unavailable.

## Current status

Results from October 2026 on macOS 27 with the Firefox packages:

| Extension | Status |
| --- | --- |
| Dark Reader | Light and dark modes work, separately per account |
| Simple Translate | Whole-page translation opens in an extension page |
| Bitwarden | Login, save, autofill, lock, and restart work with the Firefox profile. With Standard, the popup does not start. Passkeys are untested. |
| LastPass | Field icons and autocomplete work (manual report). One content-script warning remains. |
| Grammarly | Popup stays on its starting screen. Cause unresolved. |
| Tampermonkey | Firefox package rejected for an empty `content_scripts` entry |

Chrome builds of the same extensions behaved the same or worse in WebKit, so
Firefox stays the package source.

## Run the investigations

All live checks use the **Paguro Extension Compatibility** scheme. Set the
package with the `PAGURO_EXTENSION_PROBE_SLUG` build setting. A shell variable
alone does not reach the test runner. Keep result bundles in `.project/`, out
of Git.

Runtime check in three browser identities (default, Safari, Firefox):

```sh
xcodegen generate
xcodebuild -project Paguro.xcodeproj \
  -scheme 'Paguro Extension Compatibility' -configuration Debug \
  PAGURO_EXTENSION_PROBE_SLUG=bitwarden-password-manager \
  -only-testing:PaguroTests/BrowserExtensionCompatibilityTests/testRuntimeInvestigationWhenExplicitlyRequested \
  -resultBundlePath .project/extension-compatibility/runtime-001.xcresult test
```

Firefox and Chrome package comparison (one slug at a time):

```sh
xcodebuild -project Paguro.xcodeproj \
  -scheme 'Paguro Extension Compatibility' -configuration Debug \
  PAGURO_EXTENSION_PROBE_SLUG=simple-translate \
  -only-testing:PaguroTests/ExtensionSourceComparisonTests/testFirefoxAndChromePackagesWhenExplicitlyRequested \
  -resultBundlePath .project/extension-compatibility/source-001.xcresult test
```

Each run writes a JSON attachment per case. A passing test means the report
was collected, not that the extension worked, so read the report. Export
attachments with `xcrun xcresulttool export attachments`.

These probes run in fresh, throwaway accounts. They never touch your real
services or vaults, and the observer code lives only in the test target. The
Chrome downloader also lives only in tests. It is not a Chrome installer.

## Vendor-independent checks

These run in the normal suite with synthetic extensions and no network:

- `ExtensionCompatibilityProbeTests`: messages, ports, storage, alarms, and
  script injection, as positive controls.
- `ExtensionAPIContractTests`: the `scripting.ExecutionWorld` shim, including
  that it adds nothing when the permission is missing.
- `ExtensionLifecycleContractTests`: one menu registration across activation,
  navigation, reload, and controller recreation.

When a vendor package fails, first reproduce it with a small synthetic
extension under the same manifest and permission conditions.

## Password manager checks

Use the local fixture page `https://localhost:8443/vault-login.html` in two
separately added services, with a disposable vault. Check that:

1. The second service stays signed out and cannot see the first one's items.
2. Lock now asks for unlock, and autofill works again after unlock.
3. After Command-Q and relaunch, the vault asks for unlock and keeps its items.

Keep master passwords out of logs and chat.

## References

- [Browser extensions](BROWSER-EXTENSIONS.md)
- [Apple: unsupported API declarations](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/unsupportedapis)
- [Chromium: CRX3 format](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/crx_file/crx3.proto)
