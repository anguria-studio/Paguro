# Design choices

Paguro uses native macOS controls and behavior. Prefer standard controls over
custom controls when they meet the user's needs.

## Workspaces and services

Keep services together in the main window. Use the sidebar to organize
workspaces and accounts, and the toolbar for navigation and service controls.
Use "workspace" in user-facing text. Each service account keeps a separate
session, even when two accounts use the same website.

The custom-service form discovers the website icon while the user enters the
address. Place its compact preview beside the name and address, with a native
Change Icon menu. Keep manual URL overrides in the service editor. Adding a
service must not wait for icon discovery.

## Appearance

Use semantic colors that adapt to light and dark appearance. Liquid Glass is
available on macOS 26; macOS 15 uses the fallback surface materials.
Preserve readable text, visible selection, and distinct notification cards
when Reduce Transparency or Increase Contrast is enabled.

Keep service website styling separate from the native application shell.
Do not assume that a website follows the app's appearance preference.

## App and menu-bar icons

The app icon uses the layered Paguro shell. Default appearance has a light
purple gradient. Dark appearance has a lavender shell over the standard black
gradient. Keep the editable layers in `Paguro/AppIcon.icon`.

The menu-bar shell uses a 20 point vector template with thin transparent spiral
seams. macOS supplies its light or dark tint. The menu-bar window uses the same
asset in its header. The status item uses 45 percent opacity during global
mute, quiet hours, or when every configured service is muted. An empty service
list does not imply mute. The Dock shows a muted-bell overlay in its top-right
corner for the same state. The notification counter is hidden while this overlay appears.

The menu-bar window header groups notification mute, Lock, and Settings on the
right. All three use the same circular toolbar surface. The app name and shell
mark open the main window. The window has no footer.
Show Lock only when App Lock is enabled and Paguro is unlocked.

## Notifications and the island

The notch island is optional. Use macOS notifications on displays without a
notch. Keep notification detection separate from presentation.

Global, workspace, and service mute also pause audio and video in the affected
service views. Global mute controls in the header and menu bar share one state.
Their help and accessibility labels name both notifications and media.

Make notification controls usable with a pointer, keyboard, and VoiceOver.
Scroll focused cards into view. Keep dismiss controls available while their
card or button has hover or keyboard focus. Respect Reduce Motion.

## Accessibility

Use descriptive accessibility labels and a logical focus order. Make each
custom control keyboard accessible and show a clear focus state.
Do not use color alone to communicate status or selection.

## Configuration and recovery

Use Export Configuration and Import Configuration for routine setup copies.
Place Configuration at the bottom of General settings, after Accessibility.
Keep automatic snapshots in the background. Offer restore through recovery
notices when Paguro detects a data problem, instead of a routine Settings control.

## App lock

Showing the lock screen does not request authentication. Start Touch ID or
password authentication only when the user activates Unlock. Cancelling the
prompt leaves the lock screen in place.

## Updates

Use Sparkle's standard update dialogs in the direct-download build. Put
Check for Updates in the app menu and About settings. Keep the automatic-check
preference in About settings. Development builds omit update controls.

Feature documents describe the behavior and constraints for each component.
Update this overview when a shared design rule changes.
