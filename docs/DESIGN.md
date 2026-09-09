# Design choices

Blatta uses native macOS controls and behavior. Prefer standard controls over
custom controls when they meet the user's needs.

## Workspaces and services

Keep services together in the main window. Use the sidebar to organize
workspaces and accounts, and the toolbar for navigation and service controls.
Use "workspace" in user-facing text. Each service account keeps a separate
session, even when two accounts use the same website.

## Appearance

Use semantic colors that adapt to light and dark appearance. Liquid Glass is
available on macOS 26; macOS 15 uses the fallback surface materials.
Preserve readable text, visible selection, and distinct notification cards
when Reduce Transparency or Increase Contrast is enabled.

Keep service website styling separate from the native application shell.
Do not assume that a website follows the app's appearance preference.

## Notifications and the island

The notch island is optional. Use macOS notifications on displays without a
notch. Keep notification detection separate from presentation.

Make notification controls usable with a pointer, keyboard, and VoiceOver.
Scroll focused cards into view. Keep dismiss controls available while their
card or button has hover or keyboard focus. Respect Reduce Motion.

## Accessibility

Use descriptive accessibility labels and a logical focus order. Make each
custom control keyboard accessible and show a clear focus state.
Do not use color alone to communicate status or selection.

## Updates

Use Sparkle's standard update dialogs in the direct-download build. Put
Check for Updates in the app menu and About settings. Keep the automatic-check
preference in About settings. Development builds omit update controls.

Feature documents describe the behavior and constraints for each component.
Update this overview when a shared design rule changes.
