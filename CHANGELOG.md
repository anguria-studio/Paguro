# Changelog

Changes that affect Paguro users appear here, with the newest release first.

## [Unreleased]

## [1.0.0] — 2026-09-10

First public Paguro release, based on [Chorus](https://github.com/nicojan/Chorus)
by Nico Jan. Version 1.0.0, build 4.

### Added

- A native macOS window with workspaces and a compact service rail. Each service
  account keeps a separate login session.
- Native notifications, unread badges, mute controls, and an optional
  notification island near the notch.
- Hibernation for idle services, plus ad and tracker blocking.
- App lock with Touch ID or your Mac password. Notification content stays
  hidden while the app is locked.
- Camera and microphone controls, keyboard navigation, and service appearance
  settings.
- Configuration export and import, with options to add to or replace the
  current setup. Login sessions stay on the original Mac.
- A signed, notarized DMG and signed updates through Sparkle.

### Compatibility

- Requires macOS 15 or later, on Apple silicon or Intel.
- Liquid Glass requires macOS 26. Earlier systems use the fallback appearance.
- Earlier development builds use a different app identity. Export and import
  your configuration, then sign in to each service again.

[Unreleased]: https://github.com/anguria-studio/Paguro/compare/v1.0.0...main
[1.0.0]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.0
