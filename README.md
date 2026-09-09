# Paguro

**Paguro is a free, open-source fork of [Chorus](https://github.com/nicojan/Chorus).**

[Nico Jan](https://github.com/nicojan) created Chorus. Paguro builds on its native
macOS and WebKit foundation. Paguro is a separate project that preserves the
upstream copyright notices and Git history.

Paguro brings web services into one macOS app, with workspaces and separate
login sessions for each account. It adds native notifications and an optional
notification island near the MacBook notch.

All Paguro features are free. There is no Paguro subscription or paid tier.
The application source is available under the [MIT License](LICENSE).
Third-party services can require their own accounts or subscriptions.
Bundled data and dependencies have their own licenses; see
[Third-party notices](THIRD_PARTY_NOTICES.md).

## Release status

The first public release, **1.0.0**, is being prepared. There is no public Paguro
download yet. The local signed builds and Sparkle update path have passed their
initial checks; public download and final release checks are still pending.

## What Paguro provides

- Workspaces for organizing services and multiple accounts.
- Separate WebKit session storage for each service account.
- Native notifications and an optional notch island.
- App locking and notification privacy while locked.
- Configuration export and import without login sessions.
- Signed updates in the direct-download build.

Third-party websites control their own features and sign-in requirements.
Paguro does not guarantee support for every website feature.

## Install on a Mac

Paguro requires **macOS 15 or later**, on Apple silicon or Intel.
Liquid Glass requires macOS 26; earlier systems use the fallback appearance.
You do not need Xcode to use a downloaded release.

Once the first release is published:

1. Open the [Paguro releases page](https://github.com/anguria-studio/Paguro/releases).
2. Download the `.dmg` attached to the latest stable release.
3. Open the disk image and drag **Paguro.app** into **Applications**.
4. Open Paguro from Applications and follow the setup prompts.
5. Add your services and sign in to each account.

Direct releases use Developer ID signing and Apple notarization.
Allow notifications if you want macOS banners. Services ask for camera or
microphone access when needed. Paguro itself does not need an account.

For updates, choose **Paguro → Check for Updates…**. You can enable automatic
checks in **Settings → About**. Builds made before Sparkle integration need
one manual installation of a newer DMG.

## Your data

Service sessions stay in separate WebKit stores on your Mac. Paguro does not
sync login sessions or send app telemetry. The websites you open connect to
their providers and follow those providers' privacy policies.
Closing the main window keeps Paguro running in the menu bar. Choose
**Paguro → Quit Paguro** or press **⌘Q** to stop service activity.

## Build requirements

- Xcode 26 or later, with Swift 6
- macOS 26 for building the Icon Composer app icon
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

The built app supports macOS 15 and later. Vale is optional for local writing
checks; GitHub Actions checks documentation on pull requests.

## Build the app

```sh
git clone https://github.com/anguria-studio/Paguro.git
cd Paguro
xcodegen generate
xcodebuild \
  -project Paguro.xcodeproj \
  -scheme Paguro \
  -configuration Debug \
  build
```

You can also open `Paguro.xcodeproj` in Xcode, choose the **Paguro** scheme,
and press **⌘R**. Use **Paguro Island Preview** to test a simulated notch.
Development builds do not contain Sparkle. See [Distribution](docs/features/DISTRIBUTION.md)
for the signed direct-release build process.

Run the core tests with this command:

```sh
swift test --package-path Core
```

Run the app tests with this command:

```sh
xcodebuild \
  -project Paguro.xcodeproj \
  -scheme Paguro \
  -configuration Debug \
  test
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Design choices](docs/DESIGN.md)
- [Dependency policy](docs/DEPENDENCIES.md)
- [Native shell](docs/features/NATIVE_SHELL.md)
- [Application lifecycle](docs/features/APP-LIFECYCLE.md)
- [Notification system](docs/features/NOTIFICATIONS.md)
- [Island and notch support](docs/features/ISLAND.md)
- [Web sessions](docs/features/WEB-SESSIONS.md)
- [Web appearance](docs/features/WEB-APPEARANCE.md)
- [Service icons](docs/features/SERVICE-ICONS.md)
- [Compatibility fixture](docs/features/COMPATIBILITY.md)
- [Distribution](docs/features/DISTRIBUTION.md)

## Project links

- [Source repository](https://github.com/anguria-studio/Paguro)
- [Issue tracker](https://github.com/anguria-studio/Paguro/issues)

## License

Paguro uses the MIT License.
See [LICENSE](LICENSE).

Service names and logos belong to their respective owners.
Paguro uses them only to identify a service.
