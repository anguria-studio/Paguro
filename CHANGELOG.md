# Changelog

Changes that affect Paguro users appear here, with the newest release first.

## [Unreleased]

### Fixed

- Global, workspace, and service mute now silence website audio, including the
  selected service. Audio and video playback pause while muted.

## [1.0.2] — 2026-09-11

Version 1.0.2, build 7.

### Changed

- Settings now uses configuration export and import for saving and restoring
  a setup, at the bottom of the General tab. Automatic backups remain available
  through recovery prompts when Paguro detects a data problem.

## [1.0.1] — 2026-09-11

Version 1.0.1, build 6.

### Changed

- Added Lock and moved Settings beside notification mute in the menu-bar
  header. Removed the footer; the Paguro name and icon open the main window.
  Lock appears only when App Lock is enabled and Paguro is unlocked.

### Fixed

- The lock screen now waits for Unlock before requesting Touch ID or the Mac
  password. Locking the app no longer starts an authentication prompt.

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

[Unreleased]: https://github.com/anguria-studio/Paguro/compare/v1.0.2...main
[1.0.2]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.2
[1.0.1]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.1
[1.0.0]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.0
