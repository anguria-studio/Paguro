# Island and notch support

Status: in progress

## Purpose

The island gives the user a small view of current Atoll activity.
It can show a new event and a few common controls.

The island is not the notification engine.
It receives validated events from the notification pipeline.

## State and queue rules

`NotificationIslandReducer` owns the pure state rules in `AtollCore`.
It does not create a panel or start a timer.

The model has these phases:

- hidden;
- collapsed;
- alert;
- expanded;
- dismissed.

The dismissed phase keeps the current event until the exit animation ends.
The next queued event then becomes the current alert.

The pending queue is in memory only.
It keeps at most four events by default.
If the queue is full, it removes the oldest pending event and keeps the new event.
The counter still counts every additional event while the current alert is visible.
It shows `99+` when the count is greater than 99.
When the current alert ends, Atoll continues with the four most recent previews.
The state clears all event content when Atoll stops.

## Product states

### Collapsed

The collapsed state is quiet.
It can show the active service and a small unread signal.

### Alert

The alert state shows one recent event.
It stays visible for a short and testable time.

The standard alert time is six seconds.
VoiceOver gets twelve seconds.
The dismissed transition lasts 180 milliseconds.
Each queued event gets its complete alert time after it becomes current.

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

`IslandPanelController` creates its panel only after an island event needs it.
The panel starts hidden and does not activate Atoll.
The controller owns no notification detection.
The notification router supplies normalized events through a service presenter.
Island routing is off by default. The user can enable or disable it in
Notification settings. Disabling the route hides the panel immediately.
Application shutdown closes the panel and rejects later events.

The panel must not take keyboard focus in the collapsed state.
The expanded state can take focus after an explicit user action.

The panel must not cover a system camera privacy indicator.
The final hardware test must verify this condition.

## Geometry abstraction

`ScreenGeometryProvider` supplies all placement data.
Feature code must not read `NSScreen` directly.

`IslandScreenGeometry` keeps the values in global screen coordinates.
`NotificationIslandGeometryPolicy` centers the notched form on the camera
housing and attaches it to the top screen edge.
On a standard display, the policy centers a floating form inside the visible
screen frame.

`SystemScreenGeometryProvider` reads a fresh `NSScreen` snapshot on request.
It uses the active Atoll window display when one exists.
It otherwise uses the primary display whose frame starts at the global origin.
It does not cache screen values.

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

Debug builds accept `--atoll-island-screen=<preset>`.
The preset values are stable strings such as `notched-14-inch` and
`two-display-arrangement`.
Release builds ignore the simulation argument.

Debug Notification settings include a test-alert action.
This action lets a person review the island without waiting for a service event.
It uses the active service name and icon when you select a service.
Release builds do not include this action.

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
