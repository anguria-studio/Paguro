# Paguro documentation

Start with these documents:

1. [Architecture](ARCHITECTURE.md)
2. [Design choices](DESIGN.md)
3. [Writing rules](WRITING.md)
4. [Dependency policy](DEPENDENCIES.md)

Major features have separate documents:

- [Native shell](features/NATIVE_SHELL.md)
- [Application lifecycle](features/APP-LIFECYCLE.md)
- [Notification system](features/NOTIFICATIONS.md)
- [Island and notch support](features/ISLAND.md)
- [Web sessions](features/WEB-SESSIONS.md)
- [Web appearance](features/WEB-APPEARANCE.md)
- [Service icons](features/SERVICE-ICONS.md)
- [Compatibility fixture](features/COMPATIBILITY.md)
- [Configuration transfer](features/CONFIGURATION.md)
- [Performance comparisons](features/PERFORMANCE.md)
- [Distribution](features/DISTRIBUTION.md)

Large decisions have a record in [decisions](decisions/README.md).

## Current guidance and history

Feature guides describe the current implementation on `main`. The changelog
records published versions; an empty Unreleased heading is a placeholder.
For an installed version, read the documents at its matching release tag.
An older feature branch can still label already released changes Unreleased.

Decision records preserve the reasoning at their recorded date. Superseded
records are not current requirements. Dated verification results establish only
what was checked then; they do not mark open hardware tests as complete.

Update a document in the same change that changes its subject.
