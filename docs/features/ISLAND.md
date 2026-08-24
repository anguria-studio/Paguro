# Island and notch support

Status: planned

## Purpose

The island gives the user a small view of current Atoll activity.
It can show a new event and a few common controls.

The island is not the notification engine.
It receives validated events from the notification pipeline.

## Product states

### Collapsed

The collapsed state is quiet.
It can show the active service and a small unread signal.

### Alert

The alert state shows one recent event.
It stays visible for a short and testable time.

A new high-priority event can replace the current event.
Equal events must not restart the timer without limit.

### Expanded

The expanded state shows recent events and controls.
The user opens this state with a click or keyboard action.

The first controls can include these actions:

- open the active service;
- mute the active service;
- turn Do Not Disturb on or off;
- switch to a recent service;
- dismiss an event.

Do not add a control that has no clear daily use.

## Window type

Use a borderless AppKit panel for exact screen placement.
SwiftUI renders the panel content.

The panel must not take keyboard focus in the collapsed state.
The expanded state can take focus after an explicit user action.

The panel must not cover a system camera privacy indicator.
The final hardware test must verify this condition.

## Geometry abstraction

`ScreenGeometryProvider` supplies all placement data.
Feature code must not read `NSScreen` directly.

The system provider uses these values:

- visible screen frame;
- safe-area insets;
- auxiliary top-left area;
- auxiliary top-right area;
- backing scale factor.

The simulated provider returns fixed test values.

## Debug simulation

macOS has no general Mac notch simulator.
Atoll therefore includes debug geometry presets.

Required presets:

- 14-inch notched display;
- 16-inch notched display;
- non-notched laptop display;
- external display;
- two-display arrangement;
- crowded left menu bar;
- crowded right menu bar.

A debug overlay can draw a black camera housing.
The overlay and the real island panel must be separate objects.

UI tests select a preset with a launch argument.
Release builds must not include the fake housing control.

## Non-notched displays

A non-notched display uses a floating form near the menu bar.
It must look intentional and must not imitate missing hardware.

The user can disable the floating form.
Native system notifications remain available.

## Multiple displays

The island follows the display that contains the active Atoll window.
When no Atoll window is active, it uses the configured primary display.

The panel must move after these changes:

- display connection or removal;
- resolution change;
- scale change;
- menu-bar display change;
- full-screen space change;
- wake from sleep.

## Visual rules

Use native Liquid Glass on macOS 26.
Keep text short and high contrast.

The collapsed state must not look like a permanent alert.
The expanded state must use a clear information order.

Use a glass transition for size changes when the system permits motion.
Use a fade or direct change when Reduce Motion is on.

## Accessibility

Every state needs one clear VoiceOver description.
The expanded controls need a logical keyboard order.

An alert must not disappear before VoiceOver can read it.
The user must have a way to open recent events again.

## Tests

Pure geometry tests cover every preset.
UI tests capture each state in light and dark appearance.

Hardware tests cover these conditions:

- a notched MacBook display;
- an external display;
- a full-screen app;
- a hidden menu bar;
- sleep and wake;
- display connection and removal;
- camera use;
- increased contrast;
- reduced transparency;
- reduced motion.
