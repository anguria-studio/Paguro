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
`com.tommasolaterza.Paguro.updatetest` and permits local networking.
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

The App Store build uses a separate configuration or target.
It must omit Sparkle and all self-update controls.

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

## Renamed release identity

The Paguro bundle uses `com.tommasolaterza.Paguro`. A signed release requires
a matching Sparkle signing account and the `paguro` notarization profile, or
the profile selected by `PAGURO_NOTARY_PROFILE`. Renaming source files does not
rename Keychain credentials or create the configured GitHub repository. Verify
these external prerequisites before building a signed release.
