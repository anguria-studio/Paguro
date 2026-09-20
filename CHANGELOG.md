# Changelog

Changes that affect Paguro users appear here, with the newest release first.

## [Unreleased]

- Setup now has two steps: welcome and service selection. Choose several
  services from a full-page catalog, then add them together. Search, categories,
  Back, and custom websites keep the selection until the final Add.

- The welcome screen offers "Turn on" for notifications. When permission is
  off, it opens Paguro’s own notification controls in System Settings.

- First Run Preview starts with disposable services and sign-ins on every run.
  Floating notices sit directly below the header without a second title-bar gap.

- Backup offers, offline status, and microphone feedback use floating cards
  over the window, including the welcome screen. Store errors keep their strip.

- A new setup starts without workspaces. Adding the first service creates Home
  in the same save. The first-run preview ends after a successful add or import.

### Added

- Paguro starts with a welcome screen where you add your first service, instead
  of a set of example services. It tells you what Paguro does. It offers
  notifications and, on a Mac with a notch, island alerts. One button opens
  service selection, and a quiet line under it imports a configuration from
  another Mac. The sidebar and the header appear as soon as that first service exists,
  and the screen returns if you ever remove every service.

- You can install Paguro with Homebrew:
  `brew install --cask anguria-studio/tap/paguro`. The cask installs the same
  signed and notarized disk image as the download. Paguro still updates itself.

## [1.0.5] — 2026-09-19

Version 1.0.5, build 14.

### Added

- Music and video that play when you switch to another service keep playing, for
  example Spotify and YouTube. The service that plays shows a speaker mark in
  the rail and in the menu-bar window, and its context menu offers Pause Audio.
  Muting the service still silences it. A page that starts to play after you
  leave it stays quiet, and a service that only shows a silent animation earns
  no mark.
- A download mark rises from the page into the download control in the header
  when a download starts. It shows you where the file went. Several downloads
  that start together send one mark, and the control keeps the count. Reduce
  Motion replaces the movement with a short fade at the control.
- A live service page can handle its original notification click, allowing a
  provider to open the related conversation when it supplies no destination URL.
- A notice explains the first service that Paguro releases to control memory.
  It names the service, states how many services stay loaded, and points to
  Keep Loaded. It appears one time for each time you start Paguro, as a
  floating card in the top right corner of the browser.

### Changed

- The download control in the header is now one download center for the whole
  app, like the one in a browser. It shows the downloads of every service.
  Switching service no longer hides a running download or its history. Each line
  names the service that started it, with that service's icon. A secondary click
  offers a route back to that service. Clear All empties the whole list. It now
  reads as a menu item, and the row turns blue under the pointer or keyboard
  focus. A download that starts in a service you are not reading reports
  itself with a short fade at the control. No mark rises from the page for it.
- Small text in the Paguro windows is larger and easier to read. The
  notification island and the unread count badges keep the sizes that their
  fixed spaces were built for.
- Performance settings state how many services Paguro keeps loaded at the same
  time. Paguro can release the oldest non-messaging services even when idle
  hibernation is off.
- The passkey notice appears as a floating card in the top right corner of the
  browser, instead of a bar above the page. The page keeps its full height.
  You can drag a floating card to the right to dismiss it, like a macOS
  notification. The close button still dismisses it as well.
- The Add Service sheet no longer repeats the passkey notice. The floating card
  still shows it the first time you open a service.

### Fixed

- A service in a call keeps its sound when you switch to another service. Paguro
  pauses the sound of a service that you leave, to keep a background page quiet.
  That rule also silenced the other person in a call, while your microphone kept
  sending. A service that holds the camera or the microphone now keeps its sound
  until the call ends. Muting the service still silences it.
- A long icon rail keeps its icons on the rail centerline when it scrolls. The
  rail no longer shows the system scroll bar. That scroll bar took width from
  the icons and pushed them left, when the system setting for scroll bars is
  Always. A thin indicator over the trailing edge now shows the scroll position
  while you scroll, and it fades out when you stop.
- The expanded island keeps its count badge and its Clear All button inside the
  camera housing. Both controls start below the top screen edge and never reach
  below the bottom edge of the notch. They stay easy to read and to hit, also at
  a larger system text size.
- Prevent a queued quiet-hours check from accessing the store after shutdown.
- A notification without a destination no longer reloads the service root after
  selecting the service.

## [1.0.4] — 2026-09-12

Version 1.0.4, build 11.

### Fixed

- Island notifications resume after unlocking when Paguro starts locked with
  the island enabled, without needing to turn the setting off and on.
- Island notifications use the same default sound as macOS banners. Lock, mute, and
  quiet hours keep them silent.
- The island uses one continuous background instead of drawing a second black
  notch. Compact alerts stay aligned with the top screen edge.
- The Paguro service tile has a larger visual size beside other rail icons,
  with the same adjustment in light and dark appearance.
- Clear All dismisses island cards in a short stagger, then smoothly shrinks
  the empty island. Reduce Motion uses a simple fade.

## [1.0.3] — 2026-09-12

Version 1.0.3, build 9.

### Added

- Notification Test in the service catalog lets users try notifications,
  unread badges, and the island without a messaging account.

### Changed

- Custom services now preview their website icon while you enter the address.
  A compact Change Icon menu replaces the manual fetch controls in Add Service.
- Website icon discovery prefers page-declared icons and manifests before
  conventional root filenames, preserving page-specific branding.
- The lock screen follows the window glass and transparency settings while
  keeping service content hidden.

### Fixed

- Global, workspace, and service mute now silence website audio, including the
  selected service. Audio and video playback pause while muted.
- New macOS and island notifications use favicons fetched after a service
  opens, without restarting Paguro.

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
  Lock appears only after you turn on App Lock and unlock Paguro.

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
- App lock with Touch ID or your Mac password. Paguro hides notification
  content while it stays locked.
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

[Unreleased]: https://github.com/anguria-studio/Paguro/compare/v1.0.5...main
[1.0.5]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.5
[1.0.4]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.4
[1.0.3]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.3
[1.0.2]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.2
[1.0.1]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.1
[1.0.0]: https://github.com/anguria-studio/Paguro/releases/tag/v1.0.0
