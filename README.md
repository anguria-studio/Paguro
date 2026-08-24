# Atoll

Atoll is a native macOS workspace for web services.

It keeps each service account in a separate WebKit data store.
It also provides native controls, notifications, and a small island near the MacBook notch.

Atoll is in early development.
Do not use it as your only way to access an important account.

## Product goals

- Use native macOS controls and behavior.
- Keep account data local and separate.
- Show useful notifications without a service API.
- Stop all work after the user quits the app.
- Use public Apple APIs.
- Keep the code clear and easy to test.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Vale is optional for local work.
The build service runs Vale for each pull request.

## Build the app

```sh
xcodegen generate
xcodebuild \
  -project Atoll.xcodeproj \
  -scheme Atoll \
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
  -project Atoll.xcodeproj \
  -scheme Atoll \
  -configuration Debug \
  test
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Design choices](docs/DESIGN.md)
- [Backlog](docs/BACKLOG.md)
- [Error and gotcha log](docs/ERRORS.md)
- [Notification system](docs/features/NOTIFICATIONS.md)
- [Island and notch support](docs/features/ISLAND.md)
- [Web sessions](docs/features/WEB-SESSIONS.md)
- [Distribution](docs/features/DISTRIBUTION.md)

## Project links

- [Source repository](https://github.com/tommasoltrz/Atoll)
- [Issue tracker](https://github.com/tommasoltrz/Atoll/issues)

## Project history

Atoll uses [Chorus](https://github.com/nicojan/Chorus) as its code base.
Chorus is an MIT-licensed project by Nico Jan.
The Git history keeps the upstream work and its authorship.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for other sources and licenses.

## License

Atoll uses the MIT License.
See [LICENSE](LICENSE).

Service names and logos belong to their respective owners.
Atoll uses them only to identify a service.
