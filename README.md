# Blatta

Blatta is a native macOS workspace for web services.

It keeps each service account in a separate WebKit data store.
It also provides native controls, notifications, and a small island near the MacBook notch.

Blatta is in early development.
Do not use it as your only way to access an important account.

## Product goals

- Use native macOS controls and behavior.
- Keep account data local and separate.
- Show useful notifications without a service API.
- Stop all work after the user quits the app.
- Use public Apple APIs.
- Keep the code clear and easy to test.

## Requirements

- macOS 15 or later (Liquid Glass needs macOS 26)
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Vale is optional for local work.
The build service runs Vale for each pull request.

## Install

Blatta is signed with a Developer ID and notarized by Apple, so a downloaded
build opens on a double-click. Drag `Blatta.app` from the disk image to
`/Applications`.

## Build the app

```sh
xcodegen generate
xcodebuild \
  -project Blatta.xcodeproj \
  -scheme Blatta \
  -configuration Debug \
  build
```

Run the core tests with this command:

```sh
swift test --package-path Core
```

Run the app tests with this command:

```sh
xcodebuild \
  -project Blatta.xcodeproj \
  -scheme Blatta \
  -configuration Debug \
  test
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Design choices](docs/DESIGN.md)
- [Backlog](docs/BACKLOG.md)
- [Error and gotcha log](docs/ERRORS.md)
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

- [Source repository](https://github.com/tommasoltrz/Atoll)
- [Issue tracker](https://github.com/tommasoltrz/Atoll/issues)

## Project history

Blatta uses [Chorus](https://github.com/nicojan/Chorus) as its code base.
Chorus is an MIT-licensed project by Nico Jan.
The Git history keeps the upstream work and its authorship.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for other sources and licenses.

## License

Blatta uses the MIT License.
See [LICENSE](LICENSE).

Service names and logos belong to their respective owners.
Blatta uses them only to identify a service.
