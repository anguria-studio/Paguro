# Island and notch support

Status: in progress

## Purpose

The island gives the user a small view of current Paguro activity.
It can show a new event and a few common controls.

The island is not the notification engine.
It receives validated events from the notification pipeline.

## State and history rules

`NotificationIslandReducer` owns the pure state rules in `PaguroCore`.
It does not create a panel or start a timer.

The model has these phases:

- hidden;
- collapsed;
- peek;
- alert;
- expanded;
- dismissed.

The dismissed phase keeps the current event until the exit animation ends.
It then returns to the collapsed state.

The recent list keeps all events that Paguro receives in the current session.
It is in memory only. The count shows `99+` when it is greater than 99.
Opening or dismissing one event decreases the count by one. Clear All clears
the count and the recent list.

The island also drops the events of one service account when the user reads
that conversation in Paguro. Two conditions start this rule:

- the user selects that service account in the main window, or Paguro becomes
  the active application with that service account active;
- the unread count of that service account becomes zero.

The count then decreases by the number of removed events. The island keeps the
events of the other service accounts. It collapses when the list becomes empty.
A compact alert of that service account uses the dismissed transition.

A burst does not create a sequence of compact alerts. Each new event replaces
the compact preview and restarts one display time. The recent view keeps all
session details in newest-first order.
Hiding or stopping the island clears the recent list and count.
The state clears all event content when Paguro stops.

## Layout rules

`NotificationIslandLayout` owns the pure layout rules in `PaguroCore`.
It holds constants only and it measures no view.

The type uses these values:

- row height: 68 points;
- row spacing: 8 points;
- row pitch: 76 points;
- top inset: 4 points;
- bottom inset: 8 points;
- toolbar horizontal inset: 14 points;
- card horizontal inset: 10 points;
- card corner radius: 12 points;
- card vertical padding: 7 points;
- visible row limit: 3 rows;
- stack peek: 38 points;
- stop line inset: 10 points;
- pile stagger: 8 points;
- bottom scroll clearance: 10 points;
- maximum fold depth: 3 levels;
- expanded body width: 420 points.

The card inset is smaller than the toolbar inset. Each card therefore extends
4 points past the toolbar capsules on each side.

The visible row count is the event count, but not less than 1 and not more
than 3.

The expanded and peek panel height is the sum of these values:

- the camera-housing toolbar height;
- the top inset;
- the visible row count times the row height;
- the row spacing between the visible rows;
- the bottom inset.

An event count greater than 3 adds the 38-point stack peek to this height. The
list then scrolls.

A 38-point camera housing gives these heights:

- 118 points for zero events or one event;
- 194 points for two events;
- 270 points for three events;
- 308 points for four events or more.

The height comes from the event count. Do not measure it from SwiftUI. AppKit
stays the only owner of the panel frame. The Window type section gives this
rule in full.

## Product states

### Collapsed

The collapsed state is quiet.
The collapsed island's counter wings are always solid black. They keep this
black surface in every glass style and transparency setting, as an extension
of the camera housing. The collapsed background continues behind the camera.
It shows the unreviewed count when that count is not zero.
The counter badge stays legible on the black surface.
Clicking it pins the expanded state open.
Moving the pointer over it opens the complete recent view without activating
Paguro when history is not empty.

The island collapses completely when the pointer leaves it. This pointer rule applies
to the hover view and to the pinned expanded view. The collapse starts 180
milliseconds after the pointer leaves. Pointer reentry inside this delay
cancels the collapse.

The controller compares the real pointer position with the island frame before
it collapses the island. This test frame adds a 6-point margin at the two sides
and at the bottom. It extends to the top screen edge. The island stays open
when the pointer is inside that frame. The controller then tests the position
again every 250 milliseconds until the pointer is outside. Pointer reentry
cancels the test. This rule prevents the collapse-and-expand loop that a size
change or the top screen edge can cause.

### Alert

The alert state shows one recent event.
It stays visible for a short and testable time.

The standard alert time is four seconds.
VoiceOver gets twelve seconds.
The dismissed transition lasts 180 milliseconds.
A new event replaces the compact preview and restarts the standard alert time.
Hovering the alert opens the complete recent view and pauses its compact timer.

The compact alert does not continue its remaining display time after a hover.
The 180-millisecond dismissed transition runs and the island returns to the
collapsed state. The counter and the recent list keep their content.
Each recent card has a dismiss action.

### Expanded

The recent view shows the session events in a vertical stack. The newest event
is on top. The list has no upper limit and it scrolls.

Each visible card is full size, sharp, and interactive.
Only a card at the bottom of the scroll area changes.

The scroll view spans the complete island height. A leading spacer holds the
list below the toolbar. That spacer equals the camera-housing height plus the
top inset. Cards scroll under the toolbar and disappear at the island's top
edge. The scroll view does not clip its content. The island shape is the only
clip.

The count badge and the Clear All button sit on frosted capsules. These
capsules use the regular material. Reduce Transparency replaces that material
with an opaque window background. The island background continues across the
camera area. The toolbar reserves this space without a black camera replica.
Both capsules use the same resting background. Clear All adds a tint only
when it has keyboard focus.
The physical camera can obscure a card while it scrolls behind the toolbar.

The stop line sits 28 points below the bottom edge of the third card. A card
stops at this line when
its bottom edge reaches it. Its depth is the distance past the line divided by
the row pitch. The depth stops at 3. Three events or fewer create no fold.

The card holds the stop line without motion from depth 0 to depth 1. The card
above it slides over it in this range. From depth 1 to depth 2 it eases 8
points down and becomes the second strip. It scales by 6 percent for each
level, anchored at its bottom edge, and reaches 0.88 at level 2. It fades out
between depth 2 and depth 3. Paguro hides it at depth 3 and builds no view for
it.

At the end of the scroll the last card lands exactly on the stop line.
It then shows all of its content.
The deepest strip ends 10 points above the bottom edge of the island.
Three events or fewer end the last card 8 points above that edge.

The recent view never shows a scroll indicator. A mouse does not show one
either.

Light appearance uses near-white cards above a soft gray island surface.
Dark appearance uses light translucent cards above the dark surface.
Reduce Transparency keeps this hierarchy with opaque fills: light cards use
97 percent white over an 86 percent white background. Focus brightens the
card. Card edges and dismiss controls
use dark accents in light appearance and light accents in dark appearance.
Expanded counters use the primary text color; collapsed counters stay white.
A card first erases the cards behind it
with a destination-out blend of its own shape. It then draws its fill, a
1-point hairline border, and its content. The list puts these steps in one
compositing group. Overlapping cards therefore never add up. When transparency
is enabled, the screen stays visible through the front card. The front card hides the
covered card, and the border marks the edge between the two. Paguro never clips
or fades the card content.

The row computes its depth, offset, scale, and opacity in one `visualEffect`.
It uses its frame in the scroll view and the measured scroll-area height. It
uses the layout rule when no measurement exists. The transforms therefore
follow the scroll position in the render phase without state lag. Row state
holds a hidden flag only. Do not nest a visual effect inside the card. Do not
use `bounds(of:)`.

Reduce Motion keeps the offset and the fades and removes the scale.

Dismissing a card animates that card out. The card fades, shrinks a little, and
moves to the right. The remaining cards spring into their new positions. The
panel height shrinks in the same 280-millisecond frame transition.
A new event slides in from the top.
Reduce Motion replaces these animations with a fade.
Each card shows its dismiss button centered six points inside the top-right corner on pointer
hover, keyboard focus, or VoiceOver focus. Moving onto the button keeps it
visible, including the part outside the card. The circle is 20 points wide
and keeps a 28-point pointer target. The button stays in keyboard and accessibility navigation when
visually hidden. Its space stays reserved so the text does not move.
Clear All stays visible.

Clear All clears the history immediately, but keeps the outgoing cards for a
short exit animation. Cards fade and move right from top to bottom, with a
45-millisecond stagger for the first five visible positions. Start at the
current scroll position. Deeper cards share the last delay, so a long history
never extends this step beyond 400 milliseconds.
The empty surface then shrinks to the camera area in 280 milliseconds before
it disappears. Keep its top edge and horizontal center fixed.
`NotificationIslandClearAllTiming` owns the pure timing rules in `PaguroCore`.
The renderer owns the temporary outgoing presentation and its cancellation.
Reduce Motion fades the complete island in 160 milliseconds, without stagger,
scaling, or movement. New arrivals replace the outgoing presentation and remain
in history. Lock, hiding, and quitting cancel the animation immediately.
Repeated layout updates must not restart it. The same exit sequence applies
when dismissing the last card empties the recent view.

The user can click a card and drag it to the right to dismiss it.
`NotificationIslandSwipeRule` in `PaguroCore` holds the pure rules for this
gesture. A drag starts after 8 points. The card follows the pointer only when
the first movement is more horizontal than vertical. The card moves without
resistance to the right. It resists a leftward drag at 35 percent.

A release dismisses the card in these conditions:

- the drag reaches 25 percent of the card width;
- the velocity reaches 400 points each second.

The card then slides out and the removal animation follows. A shorter drag
springs the card back. A plain click still opens the card. The dismiss button
stays for keyboard and VoiceOver users. Reduce Motion removes the leftward
resistance and the fade during the drag. A two-finger trackpad swipe stays a
scroll event and never dismisses a card.

An active drag holds the island open. The pointer can leave the island during
the drag and the island stays open. The exit delay starts at the end of the
drag when the pointer is still outside.

Hover opens a transient, nonactivating recent view. Clicking that view pins it
open. The pinned panel takes keyboard focus after this explicit action.
File > Open Notifications (Command-Shift-O) opens the recent view without a
pointer click while Paguro is active. It focuses the newest card for keyboard
and VoiceOver use. The command is disabled while locked, without a notched
display, with island alerts off, or when history is empty.
A keyboard-opened island ignores pointer exit. Escape collapses it quietly,
keeps its history, and returns focus to the previous visible Paguro window.
Clearing the list, disabling the island, and locking also close the view.
Escape returns it to the collapsed state.
The newest recent event receives initial focus when one exists.
Tab moves between event actions and Clear All.
Tab, Shift-Tab, arrow-key navigation, and VoiceOver reveal the focused card
above the bottom fold. Moving between a card and its dismiss button keeps the
scroll position. Card titles and message bodies use the system body text size.
Keyboard focus uses a brighter card with a quiet neutral edge for its open
action, or an inverted dismiss button. Controls use these custom highlights
instead of the default blue focus outlines.
Up and Down move focus between cards and scroll the focused card into view.
Backward Delete and Forward Delete dismiss the focused card.
When VoiceOver dismisses a card, keyboard and VoiceOver focus move to the next
card body. Dismissing the last card in the list uses the previous card. An
empty list collapses the island. Focus moves before the dismissed control
leaves the accessibility tree.
Return activates the focused control.

The recent view shows all session events. Each event has a service
name, event title, time, optional body, and dismiss button.
The complete card acts as the open action. The card shows no arrow glyph.
Opening an event selects the exact service account through the shared
notification route and removes that event from the recent list. Clear All
clears all session events. The count is on the left side of the camera housing.
The text button "Clear All" is on the right side. Its VoiceOver label is
"Clear all notifications". The island has no close button.

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
The panel starts hidden and does not activate Paguro.
The panel keeps one SwiftUI hosting view for its complete lifetime.
State changes update one observable presentation model.
They must not replace the hosting view.
One plain AppKit view owns the panel content area. It contains the hosting view
and gives that view an explicit frame. AppKit is the only owner of the panel
frame. Do not wrap presentation model updates in a SwiftUI animation that can
change the hosting view's ideal size.
The controller owns no notification detection.
The notification router supplies normalized events through a service presenter.
Island routing is off by default. The user can enable or disable it in
Notification settings. Disabling the route hides the panel immediately.
Application shutdown closes the panel and rejects later events.
New events use the default macOS notification sound through a sound-only
UserNotifications request. Lock and shutdown cancel pending sound requests;
restoring history is silent. See [Notification system](NOTIFICATIONS.md).
App lock hides the panel and retains existing recent events in memory. It
rejects new alerts, including previews, and ignores read-state dismissal while
locked. Unlocking restores the collapsed counter and history without replaying
a compact alert. Disabling the island or quitting still clears history.

An enabled island remains enabled when Paguro starts locked, including before
the controller has read any screen geometry. Unlocking starts screen tracking
and restores the collapsed island without requiring a settings toggle. The
panel still waits for launch activation to settle. Disabling the island while
locked cancels that pending activation.

The panel must not take keyboard focus in the collapsed state.
The expanded state can take focus after an explicit user action.

The collapsed state and visible alert receive pointer events. An empty
collapsed state does not open on hover or click. Hovering a non-empty state
opens the transient recent view. Clicking the transient surface pins it open.
Opening a recent card selects the exact service account through the shared
notification route. Each event and the complete list have dismiss actions.

The panel is wider than the visible island body. The fillets need 6 points on
each side. The panel width is therefore the visible body width plus 12 points.

These bodies use the fixed widths:

- the alert body: 360 points;
- the expanded body: 420 points.

The collapsed body is the camera-housing width plus the counter wing.

The collapsed surface grows in the horizontal direction only. It has the height
of the camera housing and does not extend below that housing. The empty
collapsed panel extends 6 points past each side of the housing. A nonzero
counter gives the panel a wider wing on the left side. These side wings supply
a public AppKit hover target. An AppKit tracking area on the panel content view
supplies the hover events.
Paguro does not try to receive events from the obscured camera area.

The panel must not cover a system camera privacy indicator.
The final hardware test must verify this condition.

## Geometry abstraction

`ScreenGeometryProvider` supplies all placement data.
Feature code must not read `NSScreen` directly.

`IslandScreenGeometry` keeps the values in global screen coordinates.
`NotificationIslandGeometryPolicy` centers the notched form on the camera
housing and attaches it to the top screen edge.
It returns no island placement for a display without a camera housing.

`SystemScreenGeometryProvider` reads a fresh `NSScreen` snapshot on request.
It uses the visible main Paguro window display when one exists.
It otherwise uses the primary display whose frame starts at the global origin.
It does not cache screen values.

`IslandScreenChangeMonitor` observes public AppKit notifications while the
island is visible. It requests a new geometry snapshot after these changes:

- the main Paguro window moves to another display;
- a display connects, disconnects, or changes resolution;
- the backing scale changes;
- the main window enters or leaves full screen;
- the active Space changes;
- the Mac wakes from sleep.

The monitor ignores the island panel's own movement.
It removes all observers when the user disables the island or quits Paguro.

The system provider uses these values:

- visible screen frame;
- safe-area insets;
- auxiliary top-left area;
- auxiliary top-right area;
- backing scale factor.

The simulated provider returns fixed test values.

## Debug simulation

macOS has no general Mac notch simulator.
Paguro therefore includes debug geometry presets.

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

Debug builds accept `--paguro-island-screen=<preset>`.
The preset values are stable strings such as `notched-14-inch` and
`two-display-arrangement`.
Release builds ignore the simulation argument.

The **Paguro Island Preview** scheme uses `--paguro-fake-notch`.
This argument keeps the real display frame and adds a simulated camera housing
to its top edge. It gives a non-notched development Mac a stable manual test
path. Release builds ignore this argument.

Debug Notification settings include a test-alert action.
This action lets a person review the island without waiting for a service event.
It uses the active service name and icon when you select a service.
Release builds do not include this action.
The action appears only with a connected notched display or one of the two
launch arguments above.

The **Paguro Island Preview** scheme also enables `--paguro-demo-notifications`.
With this Debug-only argument, **Show Test Island Alert** selects a random
configured Slack, WhatsApp, or Gmail account. It uses that account's name and
icon with one of 12 fictional messages: four for each service. Custom accounts
with a recognized service address are also eligible. The message cannot repeat
on consecutive clicks. Each click adds one alert through the normal island
presentation path, including its compact preview, hover expansion, and dismissal.

The demo does not read messages, change unread badges, or send macOS alerts.
App Lock and the island route switch still block the test action. With none of
these services configured, it falls back to the generic active-service preview.
Other schemes keep the generic preview. Release builds omit the demo catalog
and ignore the argument.

For screenshots, run `xcodegen generate`, select **Paguro Island Preview** in
Xcode, and run the app. Open Settings > Notifications and click
**Show Test Island Alert** once for each notification you need. Add the three
services to the app to make all 12 messages available; you do not need to sign in.

The island follows the display of the main window. On a notched laptop with an
external display, the test action therefore shows nothing while the main window
stays on the external display. Move the window to the laptop display for the
test.

## Non-notched displays

A non-notched display does not show the island.
When the island route is on, the notification router uses one normal macOS
notification as the fallback. This fallback also applies when the user turns
off the separate system-notification route.

This rule prevents a permanent fake island on standard and external displays.

Settings hides the island controls when no connected display has a camera
housing. The island switch, its caption, and the debug test action then have no
result to show. The check reads a fresh snapshot from `ScreenGeometryProvider`,
so it follows a docking change, a clamshell change, and a display change. It
reads every connected screen, not the selected screen only.

The check uses the same provider as the island, so `--paguro-fake-notch` and
`--paguro-island-screen` also show these controls on a development Mac without
a notch.

The router reads the camera housing of the selected display for each event, not
once at startup. Moving the window to another display therefore changes the
route for the next event.

The fallback uses the macOS notification permission. Without that permission the
user sees nothing on a display without a notch. The notification document gives
the permission rule and its Settings warning.

## Multiple displays

The island follows the display that contains the active Paguro window when that
display has a camera housing.
When no Paguro window is active, it uses the configured primary display.

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

Every island state uses a notch-like silhouette. `NotchShape` draws this
silhouette. The shape has a flat top edge on the screen edge. Two
concave 6-point fillets join the top corners to the menu bar. The bottom
corners are convex.

The bottom corner radius depends on the state:

- 10 points for the collapsed state;
- 22 points for the peek, alert, and expanded states.

Paguro draws one continuous background across the panel. There is no camera
cutout and no second black camera housing on the open surface. The toolbar
reserves the camera space for layout. A screen recording shows the continuous
surface; the physical camera obscures that area on the display itself.
The collapsed counter strip stays solid black, independent of the glass style
and transparency settings. An empty collapsed island paints nothing.

On hardware, the reserved camera rectangle comes from the gap between
`NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, when the screen has
a positive top safe-area inset. These are macOS layout bounds, not an exact
outline of the camera's rounded corners. Simulator presets use a fixed
164 by 38 point rectangle. The panel does not depend on tracing that outline.

The peek, alert, and expanded states use the shared glass and transparency
settings. Their surface follows the Window glass style and the shell
transparency setting. Reduce Transparency replaces this material with an
opaque system background. The island has no added outer border. Increase
Contrast strengthens the card edges only. In light appearance, card edges use
10 percent black normally and 30 percent with Increase Contrast.
The collapsed island stays plain black.
Apply one glass effect to the complete island content view. Do not make a
separate glass-effect shape for the background. The glass must stay behind
notification text and controls.

The collapsed state must not look like a permanent alert.
The expanded state must use a clear information order.
The recent stack must keep every visible card sharp and readable. Only a card
that passes the stop line can use scale, offset, and opacity to show depth.
A card erases the cards behind it, so translucent fills never add up.

Animate the AppKit panel frame when the system permits motion.
Use a fade or direct change when Reduce Motion is on.
Keep the panel top edge and horizontal center fixed while it changes size.
AppKit supplies the panel frame. Its hosting view adds no safe-area inset;
the island reserves the camera area itself. Open-state content aligns with
the top of that frame instead of centering a shorter layout inside it.
The standard size transition is 280 milliseconds.

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
