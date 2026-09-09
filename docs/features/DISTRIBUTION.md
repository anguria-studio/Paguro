# Distribution

Status: active

## Release order

Paguro will use direct distribution first.
An App Store build is optional and comes later.

The direct build still uses App Sandbox and Hardened Runtime.
This choice reduces risk and keeps the App Store path open.

## Direct release

The release process will perform these steps:

1. Create a Release archive.
2. Sign the app with a Paguro Developer ID identity.
3. Export the signed app.
4. Submit the app to Apple notarization.
5. Staple the notarization ticket to the app.
6. Create a DMG or ZIP file.
7. Submit the DMG to Apple notarization and staple that ticket too.
8. Sign the update item with the Paguro Sparkle key.
9. Publish checksums and release notes.
10. Verify the download on a clean user account.

The app needs its own ticket, because Gatekeeper asks Apple for a missing ticket.
A Mac that cannot reach that service rejects an app without a stapled ticket.
`scripts/build_dmg.sh` creates test disk images without Sparkle.
`scripts/build_release.py` archives and exports the direct build, verifies both
architectures, notarizes and staples the app and DMG, and signs the appcast.
It fails if signing, notarization, or signature verification fails.
It never publishes files or exports a private key.

Do not put a personal signing team in `project.yml`.
The release environment supplies signing values.

## Build feature selection

The same repository contains every edition. Select the XcodeGen specification
when building; a Git push does not select an edition.

| Specification | Release flag | Self-updates | Google icon fallback |
| --- | --- | --- | --- |
| `project.yml` | Neither | No | Available, off by default |
| `project-direct.yml` | `DIRECT_DISTRIBUTION` | Sparkle | Available, off by default |
| `project-store.yml` | `APP_STORE` | No | Excluded |

`AppDistribution` in PaguroCore owns this feature matrix. `AppCapabilities`
selects the compiled edition and exposes feature availability to the app.
Selecting both flags is a compile error. Preferences can enable an available
feature, but cannot override the distribution boundary.

Compile-time guards still exclude unavailable request paths and Sparkle types;
the direct specification alone adds the Sparkle dependency. Add new edition
rules to the central matrix and cover them with tests.

## Updates

`project-direct.yml` pins Sparkle 2.9.6 and enables `DIRECT_DISTRIBUTION` in
Release. Generate the default `project.yml` for development and island preview.
The default project contains no Sparkle dependency or update controls.

The direct build provides Check for Updates in the app menu and About settings.
About settings also provides an automatic-check preference. Sparkle asks for
permission to check automatically. The app does not send a system profile.
Sparkle owns this local preference; configuration export does not transfer it.

The production feed is:
`https://github.com/anguria-studio/Paguro/releases/latest/download/appcast.xml`.
This URL will work after the reviewed repository and first release are public.
Before that, a manual check can report that the feed is unavailable.

`Configuration/DirectInfo.plist` contains the public EdDSA key. The matching
private key must be available in the maintainer's login Keychain under account
`com.tommasolaterza.Paguro` before signing a release. Never reuse the upstream key or export this key
into the repository. Keep a separate secure backup before public distribution.
Signed feeds and archive verification before extraction are required.

The installer XPC service is enabled with the two bundle-specific Mach lookup
exceptions from Sparkle's sandbox integration guide. The downloader service is
not enabled because Paguro already has outgoing network access. Archive export
signs the framework and nested helpers with the Developer ID identity.

### Build a release

Use the `bin` directory from the official pinned Sparkle distribution:

```sh
python3 scripts/build_release.py \
  --version 1.0.0 --build 3 \
  --output .project/releases/1.0.0-3 \
  --sparkle-tools .project/sparkle-tools/bin
```

The CI workflow `direct-release-check.yml` compiles both architectures without
signing credentials. The local release script performs signing and notarization.

The output directory must not exist. The script retains the archive, exported
app, release manifest, DMG, signed appcast, and checksums. Only files under
`assets` are release downloads. Increase the build number for each update.
The first Sparkle-enabled version requires a manual installation over earlier
Paguro builds, because those builds have no active updater.

### Verify an update privately

Build an older and a newer build with
`--test-feed http://127.0.0.1:8765/appcast.xml` and separate output directories.
This option uses the isolated bundle identifier
`studio.anguria.paguro.updatetest` and permits local networking.
Serve the newer build's `assets` directory on loopback. Install and launch the
older test app from a writable directory. Use Check for Updates, install the
newer version, and confirm its build number after relaunch. Repeat with a
damaged download and confirm that installation is rejected.
Never publish these test artifacts. Production builds use HTTPS and the real
bundle identifier.

### Publish after review

Finish the repository review and migration first. Build from a clean release
commit. Create a draft `v1.0.0` release in `anguria-studio/Paguro`, attach the DMG,
`appcast.xml`, and `SHA256SUMS` from the same build, and add release notes.
Verify all enclosure URLs and signatures before publishing the draft as the
latest stable release. The latest-release URL then exposes the signed feed.
Keep old release downloads available. Do not replace an existing version's DMG.
Test the public download and feed without GitHub credentials after publication.

## App Store build

`project-store.yml` adds the `Paguro App Store` scheme to the default project.
Its Release archive supports Apple silicon and Intel. It contains no Sparkle
dependency or self-update controls. `APP_STORE` also excludes Google's favicon
fallback request and Settings control, even after configuration import.
Supply the signing team locally; do not
commit a personal team identifier.

```sh
xcodegen generate --spec project-store.yml
xcodebuild -project Paguro.xcodeproj -scheme 'Paguro App Store' \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath .project/store/Paguro.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID archive
```

Automatic signing uses Apple Development for the archive. Xcode signs again
for App Store distribution during export. Configure the Apple account in Xcode
and resolve signing requirements before export. This command does not upload
or submit the app. Use Organizer to validate and distribute the signed archive
after the privacy audit and release checks are complete.

Run `xcodegen generate` to restore the default development project.

Both builds must use public Apple APIs.
Both builds must use bundled and reviewed service recipes.

The review package needs clear test instructions.
Some features require a user account on a third-party service.

## Entitlements

The current baseline contains these permissions:

- App Sandbox;
- outgoing network access;
- Downloads folder read and write access;
- user-selected file read and write access;
- camera access;
- microphone access.

Remove an entitlement when no current feature needs it.
Add an entitlement only with a feature test and a reason.

## Privacy

`Paguro/PrivacyInfo.xcprivacy` declares app-local preferences (`CA92.1`) and
metadata of files in the app container (`C617.1`). These support shell settings,
workspace selection, cleanup and recovery state, cached-icon freshness, and
local store recovery. Both distribution variants include the manifest.

The manifest currently declares accessed APIs only. The App Store data
collection questionnaire remains a separate review, including website traffic.
The optional Google favicon lookup is excluded from the Store edition. Do not infer a completed privacy label
from this file. A public policy URL and an in-app policy link are still needed.

Apple's required-reason enforcement guidance lists iOS, iPadOS, tvOS, visionOS,
and watchOS; it does not explicitly list macOS. These declarations document
our actual use rather than assert a confirmed macOS upload requirement.
See [Apple's required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

The privacy statement must explain these facts:

- Service content loads from third-party websites.
- Session data stays in separate local WebKit stores.
- Paguro does not store account passwords.
- Paguro does not send telemetry by default.
- Paguro can show notification text from a service.
- Paguro stops all activity after the user quits it.

## License and asset audit

The release audit must review these items:

- Chorus code and notices;
- content-blocking source lists;
- generated content rules;
- service icons and trademarks;
- application icon;
- each new package dependency.

Record the result in `THIRD_PARTY_NOTICES.md`.

## Release checks

Test these cases before each public release:

- first launch on a clean user account;
- all optional permissions denied;
- each permission enabled later;
- window close and menu-bar use;
- `Command-Q`;
- sleep and wake;
- notched and non-notched displays;
- an external display;
- app update;
- damaged update rejection;
- Gatekeeper verification;
- notarization verification.

## Version policy

The first public release is planned as 1.0.0, build 3. Increase the build number
again if that candidate changes. Keep build numbers increasing across all
versions; Sparkle uses them to order updates. Use patch versions for fixes,
minor versions for compatible features, and major versions for incompatible
configuration or workflow changes. Tag public releases as `vMAJOR.MINOR.PATCH`.

## Local release credentials

The release bundle identifier is `studio.anguria.paguro`. Debug, compatibility,
and update-test builds use `.debug`, `.compatibility`, and `.updatetest` suffixes.
The existing Sparkle key stays under the Keychain account
`com.tommasolaterza.Paguro`. This label is independent of the bundle identifier.
The public key in `Configuration/DirectInfo.plist` must match that Keychain
account. Private keys stay in Keychain.

The release script selects the notarization profile in this order:

1. `PAGURO_NOTARY_PROFILE` from the environment.
2. `notary_profile` from the ignored `.project/release-config.json` file.
3. The default profile `paguro`.

An existing Apple account profile can sign releases for the new app identity.
The local JSON file stores only the profile name, never credentials.
The repository remains private until publication. A public update feed requires
a public repository and an uploaded release appcast.

Changing from the previous development bundle identifier gives the app a new
sandbox container and permission identity. Existing test data stays under the
old identifier. Export and import configuration if needed, then sign in again.
Do not change the release bundle identifier after public distribution.
