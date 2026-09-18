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

Catalog tiles prefer bundled service icons, so they match the sidebar and do
not need a website fetch before displaying the service mark.
Service rows draw the bundled Paguro tile 10 percent larger for optical
balance with flat logos. Scale the square and shell together, without changing
the row spacing.

## Appearance

Use semantic colors that adapt to light and dark appearance. Liquid Glass is
available on macOS 26; macOS 15 uses the fallback surface materials.
Preserve readable text, visible selection, and distinct notification cards
when Reduce Transparency or Increase Contrast is enabled.

A command row at the bottom of a popover list uses the menu row style. The row
takes the full width of the list and lines up with the rows above it. The
pointer, keyboard focus, and a press give it the accent highlight with white
text, like a macOS menu item. No other state draws a fill.

A rail hides the system scroll bar and draws a thin overflow indicator over its
trailing edge. A scroll bar that takes width from the rail content would move
the icons off the rail centerline.

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

Use one continuous background across the island, including behind the physical
camera. Do not draw a second black notch or cut a hole in the surface. Reserve
the camera area for layout so controls remain visible. Keep the content at the
top screen edge as the panel changes size.
New island events use the default macOS notification sound. Restoring history and
moving through the island do not play sounds.
Clear All dismisses cards in a short stagger, then shrinks the empty surface.
Keep the surface visible until the shrink finishes. Reduce Motion uses a fade.

Global, workspace, and service mute also pause audio and video in the affected
service views. Global mute controls in the header and menu bar share one state.
Their help and accessibility labels name both notifications and media.

Make notification controls usable with a pointer, keyboard, and VoiceOver.
Scroll focused cards into view. Keep dismiss controls available while their
card or button has hover or keyboard focus. Respect Reduce Motion.

## Motion

Movement reports a change that the user did not see happen. It never carries
information of its own, and Reduce Motion always keeps that information.

## Service marks

A rail cell carries at most one mark in each corner, so a new state reuses a
corner that its own rule keeps free. The speaker mark and the barred bell share
the leading corner. Mute silences a service and therefore ends its audio
exemption, so the two states never apply together. The unread badge keeps the
trailing corner in every state.

A new mark must not change a row height, an icon position, or the fixed rail
mouse surface.

A download start sends a download mark from the web content up into the header
download control. The mark keeps the x position of the control and travels
straight up, the way the system reports a download. The complete movement stays
between 0.5 and 0.7 seconds. The control plays its own entry or pulse as the
mark lands, so the handoff reads as one movement instead of two. The mark takes
no pointer input, no keyboard focus, and no place in the accessibility tree.
Reduce Motion removes the travel and keeps a short fade at the control.
The control is global, so a download that starts in a service the window does
not show keeps that same fade. A mark out of the page on screen would name the
wrong source.

Movement that reports several changes at one time groups them. Starts inside a
short window share one mark, and a limit caps how many marks travel at one time.
The count in the header stays the source of truth for how many downloads exist.

## Notices

Paguro has two notice shapes. Choose the shape from what the notice reports,
not from how important it feels.

Use the full-width strip at the top of the window for an app-level state. The
strip suits a notice that needs an action, or that stays until the state
changes. Store recovery, the backup offer, the offline state, and the
microphone feedback use this shape.

Use the floating card above the web content for a transient, informational,
notice about one service. The card suits a notice that reports a fact and then
leaves on its own. The capacity release and the passkey limit use this shape.

The card follows these rules:

- It floats over the top trailing corner of the web content, inset 14 points
  from the content edges. It never covers the find bar. The card stack moves
  below the find bar while the find bar is open.
- It keeps a comfortable reading width of 350 points. A narrow window reduces
  the width and keeps the margin on both sides.
- Two cards stack downward with a 9 point gap. The newest card takes the top
  place.
- It slides in from the trailing edge with a fade, and it leaves the same way.
  Reduce Motion uses a plain fade. The movement stays near 0.3 seconds.
- A drag to the right dismisses the card, like a macOS notification banner.
  The card follows the pointer, and it becomes lighter while it moves away. A
  drag to the left gives resistance and never dismisses the card. The card
  leaves when the drag passes one quarter of the card width, or when a shorter
  drag ends with enough speed to the right. A shorter and slower drag returns
  the card to its place. The drag starts only after a short movement, so a
  click still reaches the close button, and a vertical drag leaves the card
  still. The island cards and these cards share one drag rule.
- Reduce Motion keeps the drag, because the pointer moves the card directly. It
  removes the resistance to the left, the opacity change, and the slide out.
  The card then leaves with a fade.
- The close button stays the accessible way to dismiss the card. The card
  element also offers a Dismiss action for VoiceOver.
- It follows the shell glass rules. macOS 26 uses Liquid Glass, and an earlier
  system uses the material surface. Reduce Transparency uses an opaque window
  background. Increase Contrast adds a visible border. A soft shadow separates
  the card from the page.
- It takes no keyboard focus from the page, and it accepts pointer input only
  inside its own frame.
- VoiceOver reads the title and the explanation as one element and reaches the
  close button separately. Paguro announces the card when it appears.

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

The lock screen uses the same behind-window glass and protective tint as the
empty-service view. It follows Window glass and Shell transparency settings.
Hide the service content and sidebar while locked, including from hit testing
and accessibility. The glass must not reveal service content.

## Updates

Use Sparkle's standard update dialogs in the direct-download build. Put
Check for Updates in the app menu and About settings. Keep the automatic-check
preference in About settings. Development builds omit update controls.

Feature documents describe the behavior and constraints for each component.
Update this overview when a shared design rule changes.
