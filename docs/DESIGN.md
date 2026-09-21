# Design choices

Paguro uses native macOS controls and behavior. Prefer standard controls over
custom controls when they meet the user's needs.

## Workspaces and services

Keep services together in the main window. Use the sidebar to organize
workspaces and accounts, and the toolbar for navigation and service controls.
Use "workspace" in user-facing text. Each service account keeps a separate
session, even when two accounts use the same website.

The expanded sidebar footer places an icon-only Settings gear beside Add
service. Both use small native bordered buttons and disappear when the sidebar
collapses. Keep Settings out of the service header.

Selected service icons in the collapsed sidebar use a stronger neutral fill:
black at 14 percent in light appearance and white at 20 percent in dark appearance.
Keep this fill across glass presets. Increase Contrast raises it to 22 and 30
percent respectively. Expanded rows retain their existing fill and bold label.

The custom-service form discovers the website icon while the user enters the
address. Place its compact preview beside the name and address, with a native
Change Icon menu. Keep manual URL overrides in the service editor. Adding a
service must not wait for icon discovery.

Catalog tiles prefer bundled service icons, so they match the sidebar and do
not need a website fetch before displaying the service mark.
Service rows draw the bundled Paguro tile 10 percent larger for optical
balance with flat logos. Scale the square and shell together, without changing
the row spacing.

## Adding services

Add Service opens the shared selectable catalog in the browser area. Keep the
rail and native header visible, with a clear Cancel action and Add services in
the footer. Preserve the current browser session so Cancel returns without a
reload. Show the destination workspace in a text-style picker, even when only one exists.
Its New workspace action opens the name and emoji editor, then selects the new
workspace as the destination without changing the checked services or browser.
Use the same search, category menu, cards, custom website sheet, and keyboard
behavior as onboarding. Wrap the toolbar when the content pane is narrow.
Do not show wizard progress or a workspace naming field during ordinary add.

## First run

A window with no service shows a three-step wizard on the window glass.
A shared progress indicator sits between the footer actions and shows Welcome,
Your workspace, and Appearance. It stays at the same position across pages, highlights the
current step, and checks the completed step. Previous steps are clickable.
Your workspace is always available; Appearance requires a valid workspace name
and at least one selected service. The current step does not act as a button.
Step buttons use plain labels with hover and keyboard focus feedback. Navigation
never saves; only Create workspace completes setup. Content starts below the traffic
lights without a separate progress row above it.
The welcome step explains Paguro and groups notification and island setup.
The setup card uses a stronger one-point border without glass, including
Reduce Transparency and the older-system fallback. Glass keeps its light hairline.
Its fixed footer offers import on the left and "Choose your services" on the
right. The primary action opens a full-page catalog.
The second step is "Set up your first workspace". It explains that a workspace
keeps related services together. On wide windows, Workspace name sits beside
the introduction. On narrow windows, it sits below the introduction, above search.
The name starts as Personal on a new install and survives Back and custom website
entry. The step has search, category filtering, and multiple selection.
The service toolbar has a compact search field, category menu, and Custom
website button, all 36 points high. The category selector uses plain text and
a chevron, with no background or border. Its width fits the selected label and
native chevron; unselected categories do not reserve space. Resizing preserves
the same workspace editor and keyboard focus.
Selected cards have a checkmark and an accent border. A fixed footer holds
Back and Continue without a selection count. Back keeps the selection.
Continue opens Appearance without saving any workspace or service. The third
step offers Follow System, Light, and Dark themes and the four Liquid Glass
presets. Small window illustrations show light and dark themes and differences
in glass density. Use the same sample backdrop for every glass choice. These
are illustrations; the full shell previews the actual preference live. Keep
preview shapes out of the accessibility tree. Choices persist as normal preferences.
Back and stepper jumps keep the catalog filters, scroll position, workspace
name, and draft, including when returning through Welcome.
Create workspace on Appearance saves the complete service selection. A failed
save keeps the user on this step with Back and retry available. Hide the glass
selector below macOS 26. Keep appearance choices available later in Settings.
The footer puts progress above the actions when the window is too narrow for
all three steps on one row.
All setup pages share one footer outside the animated page container. It has
no separate background fill and stays stationary across steps. Only its actions
and progress state change. Keep the same content margins on every page.
Page content changes use a 0.22-second fade with 24 points of horizontal travel.
Back reverses the movement. Reduce Motion keeps only the fade. Tab reaches all
setup controls without changing the system's keyboard preferences. The grid is
one Tab stop with arrow-key movement and a dashed inset focus outline, separate
from the selection border. Mouse-down hides the outline before the grid takes
focus, so clicking never flashes it on the first card. Keyboard navigation
restores it. Space or Return toggles a card; Command-Return
advances from service selection and finishes setup on Appearance. Card selection
fades its checkmark and border over 0.14 seconds, without scaling or bouncing.
Custom website entry opens a native modal sheet over service selection, with
Cancel and Add website. It has no stepper because it is an optional editor,
not another wizard step. Its name and address fields sit beside the icon
preview and Change Icon control. URL examples are plain secondary placeholder
text, without link styling. Custom websites use the same cards as the catalog,
with their section first below search. Unchecked custom cards stay available.
Search includes their names and addresses. Returning from custom entry keeps
the catalog scroll position; selecting a new website shows its card at the top.
The rail and service header appear only after the complete selection saves.
See [Native shell](features/NATIVE_SHELL.md).

## Appearance

Use semantic colors that adapt to light and dark appearance. Liquid Glass is
available on macOS 26; macOS 15 uses the fallback surface materials.
Follow system is the default glass preference on macOS 27 and later. On
macOS 26, resolve it to Regular and offer only Off, Clear, and Regular. Earlier
systems use the solid palette without glass controls. Preserve the saved
preference across these fallbacks. On supported systems, Follow system uses
untinted native Regular glass
without extra window frost or protective color. Off, Clear, and Regular use
fixed tint and frost values, with no separate slider or reset control. Preserve
the saved preset choice; ignore legacy slider values. Clear uses standard
frosted glass without tint. It must not use Apple's Clear variant, which shows
too much background detail behind shell text.
Off uses a solid palette with a subtle violet undertone. The dark canvas is
`#18181D`, grouped surfaces and sidebar are `#202026`, and cards are `#282830`.
The light palette uses `#F5F4F7`, `#ECEBF0`, and white respectively. Apply these
colors to the opaque preset and the older-system solid fallback. Regular glass
uses the same canvas and surface hues at its existing tint opacities. Follow
system and Clear add no protective tint. Selected
service names use white in dark mode and black in light mode, with the existing
subtle row highlight instead of a blue label. Keep
system accent colors and website colors unchanged. Onboarding
keeps a uniform canvas through the footer; cards provide the surface contrast.
Preserve readable text, visible selection, and distinct notification cards
when Reduce Transparency or Increase Contrast is enabled.

Settings and Paguro-owned sheets share the shell palette and app appearance.
Use the solid canvas with glass Off, on older systems, or with Reduce Transparency.
Glass presets use native material with the shared shell tint for readable forms.
Keep native controls, grouped form surfaces, and sheet geometry. Settings hides
its default scroll background so the shared canvas also reaches the toolbar.
Workspace, service, custom website, import, recovery, and quick-switcher sheets
use the same background. System alerts, file panels, and website windows keep
their own surfaces.

A command row at the bottom of a popover list uses the menu row style. The row
takes the full width of the list and lines up with the rows above it. The
pointer, keyboard focus, and a press give it the accent highlight with white
text, like a macOS menu item. No other state draws a fill.

A rail hides the system scroll bar and draws a thin overflow indicator over its
trailing edge. A scroll bar that takes width from the rail content would move
the icons off the rail centerline.

Keep service website styling separate from the native application shell.
Do not assume that a website follows the app's appearance preference.

## Type sizes

Text that a person reads is never smaller than 12 points. The macOS system
styles `caption`, `caption2`, and `footnote` are 10 points and `subheadline` is
11, so none of them carry text in Paguro. Secondary text below the body size
shows that it is secondary with a quieter color or a heavier weight, never with
a smaller size.

One token holds this size, so the smallest text in the app is one number to
change. A site that needs a weight, monospaced digits, or a monospaced design
builds on the same token.

Explanatory text under a Settings control uses the settings caption style, which
is that same size. The style is one shared modifier, so the size, the color, and
the wrap rule stay the same in every Settings row. The color stays below the
control label, and Increase Contrast raises it.

A symbol is a picture and not text, so an `Image` keeps its own glyph size. Row
accessory marks draw at 10.5 points. The barred bell and the hibernation moon are
two of them. A larger mark would change the rail row height, the icon positions,
and the fixed rail pointer surface. A letter monogram or an emoji inside a
service tile follows the tile size. It stands for the picture that the tile has
no artwork for.

Two fixed geometries stay below the readable size. The space they sit in cannot
grow with the text.

The unread badge draws its count at 9 points. The capsule sits on a service
icon. The smallest of those icons is 18 points wide on the collapsed rail. At
the readable size the number almost fills the icon that it marks. One badge view
draws every unread count. An expanded row, an icon rail, a top bar tab, and a
workspace cell therefore show the same badge.

The island keeps the system caption styles for all of its text. That text is the
service name, the message body, the card time, Clear All, and the two count
badges. The island is not a window. Each control in it takes a height of 26, 22,
18, or 14 points from the camera housing. A card row is 68 points high. Work on
that hardware set the text sizes that fit these heights. The toolbar labels also
keep a minimum scale factor. A larger system text size therefore shrinks a
label, instead of moving a control into the screen edge or past the housing.

A source check holds this rule. It reports any font under 12 points that is not
on an `Image`. It also reads the value of a size token, so a name cannot hide a
small number. A site in a fixed geometry answers the check with a marker comment
that names the reason.

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

Use floating cards for the backup offer, offline status, microphone feedback,
capacity notice, and passkey notice. Keep the store error as a full-width strip.
The card host belongs to the window, so notices also appear over the welcome
screen and empty states. A locked window hides the cards and their announcements.

The backup offer keeps Review backups and Not now and waits for an action.
Closing or dragging it away means Not now. Offline stays until the connection
returns or the user dismisses it; the next connection loss raises it again.
Microphone feedback keeps its two-second duration. Capacity and passkey notices
keep their 12-second duration.

The card follows these rules:

- It floats over the top trailing corner of the window content, inset 14 points
  from the content edges, below the header and find bar. On the welcome screen,
  it clears the 28-point title-bar band and leaves the traffic lights usable.
  The overlay and shell share the full-window origin; do not add the hidden
  title bar's safe-area inset to the header height a second time.
- It keeps a comfortable reading width of 350 points. A narrow window reduces
  the width and keeps the margin on both sides.
- At most three cards stack downward with a 9 point gap. The newest card takes
  the top place. Persistent cards keep their places before transient cards;
  the remaining notices wait until a place is available.
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
  close button and action buttons separately. Paguro announces the card when
  it appears. Severity changes the symbol tint and keeps descriptive text.

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

The passkey explanation belongs to the app shell. It appears once for the app,
and service changes do not replace the card or restart its timer.

Use periods, commas, colons, or parentheses in UI copy. Never use em dashes.

Onboarding text fields release focus when the user clicks the background or
service grid. Return finishes editing the workspace name. Background dragging
continues to move the window.
