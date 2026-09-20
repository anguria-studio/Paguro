# Native shell

Status: active

## Purpose

The native shell gives each web service a consistent Mac interface.
It does not change the web content of a service.

## Adding services

After setup, Add Service and Command-N open a full-page catalog in the browser
area. The rail, workspace controls, and native header stay available. The same
picker serves onboarding and ordinary add, including search, category filters,
multiple selection, custom website drafts, icon previews, and keyboard controls.
The toolbar wraps into two rows in a narrow pane.

The page shows the destination workspace in a native popup. It changes the
destination without renaming a workspace. New workspace opens the name and
emoji editor, including when only one workspace exists. Create saves an empty
workspace and selects it as the catalog destination; checked services, filters,
and the current browser selection stay intact. Cancelling that editor changes
nothing. Cancelling the catalog afterward keeps the created workspace. Switching the
workspace in the rail also changes the destination and preserves the draft.
There is no wizard stepper or workspace name field here. Cancel and Add services
sit in the footer. Escape cancels; Command-Return adds the selected batch.

The batch saves all accounts and links in one transaction, appending them to
the destination in selection order. Existing services and workspace names stay
intact. A failed save retains the draft and changes no stored accounts. A
missing destination disables Add services. Choosing an already configured
catalog service creates a separate account with its own session.

Cancel returns to the previous service without reloading it. The web view stays
mounted beneath the catalog, hidden from pointer input and accessibility.
Browser navigation buttons are disabled while the catalog is open. The global
notification mute and downloads remain available. Selecting a rail service,
a quick-switcher result, a download's service, or a notification returns to
browsing. Service-switching shortcuts and incoming service links also close
the catalog. A successful add opens the first new service and closes the catalog.
The custom website and new workspace editors use modal sheets over the catalog.

## First run

The main window shows a two-step setup wizard while no service exists. A new install
starts completely empty, with no workspace and no service. Finishing setup
creates the named workspace and all selected services in one transaction.
Cancel and a failed save leave the store empty. First run names its first workspace directly, without a destination picker. Launch never seeds data.

The screen replaces the complete shell: no rail in any of the four layouts, no
content header, and no top bar. An empty rail beside an empty header said
nothing, and the window had no route to its first service except a menu.

`FirstRunPolicy` in PaguroCore holds the rule. Its input is the number of
services in every workspace together, not the services of the current
workspace. One service ends the screen, and no service brings it back. A user
who removes every service therefore sees it again, which is correct: the window
is empty again.

A shared progress indicator sits in the center of the footer, between its
actions. It labels Welcome and Your workspace, highlights the current step,
and checks the completed step. Removing the top progress row brings page
content 50 points higher, with 52 points still reserved for the traffic lights.
VoiceOver reads the current step number and name. The indicator is informational.

Welcome centers a 380-point column on the window glass. It carries the Paguro
icon, title, explanation, and grouped setup card. A fixed footer puts Import
configuration on the left and Choose your services on the right. Each page
uses the same footer baseline and side margins.

The second step is titled "Set up your first workspace". It explains that a
workspace keeps related services together for work, personal use, or a project.
A Workspace name field sits above search and defaults to Personal on a new install.
If setup appears over existing empty workspaces, it starts with the target
workspace’s current name. Back and custom website entry keep the typed name.
Create workspace requires a nonblank name and at least one selected service.
The final save trims outer whitespace and saves the name with the services.
A failed save also rolls back a changed name on an existing empty workspace.

The service catalog fills the rest of the second step. Search and a category
filter narrow the grid. Each card toggles its service, with a checkmark and an
accent border for selection. Filters and Back keep the complete selection.
`ServiceSetupSelection` in PaguroCore keeps services in selection order.

Search, category, and Custom website sit in one toolbar above the grid. All
three controls are 36 points high. The category selector shows plain text and
a chevron without a button background or border. Its width follows the current
label, including native chevron spacing. Categories appear directly in the menu,
with no submenu. Search is compact, and the workspace name
stays on its own row above the toolbar. The fixed footer holds Back and Create
workspace, with no selection counter. The primary button stays disabled until
a service is selected. The custom website sheet validates the name and HTTP(S)
address, then stages the website with the other choices. It opens as a native
modal over the catalog, with Cancel and Add website actions and no stepper.
The address example is plain, secondary placeholder text. An icon preview and Change Icon
control sit beside the fields. The draft retains the chosen or discovered icon
through the final batch save. It does not save a service by itself.

Custom websites use the same selectable cards as catalog services, including
the icon, border, and top-left checkmark. Their section comes first in the
scrolling list, directly below search and above the catalog. Unchecking a card
removes it from the batch but keeps the draft available to select again.
Search matches custom names and addresses, including unchecked drafts.
The category menu includes Custom websites once a draft exists. Adding a
custom website clears the filters and scrolls to the top so the new selected
card is visible. The catalog stays in place behind the sheet. Native modal
behavior keeps keyboard interaction in the sheet. Cancel or Escape keeps the catalog scroll
position, filters, workspace name, and selection. Setup stays on step two.

Create workspace saves all services and their workspace links together. A failed
save rolls back the complete batch and keeps the selection for retry. Each
account has its own WebKit store identifier. The shell opens on the first chosen
service. Users sign in as they visit each service. After setup, Add Service opens the same catalog in the browser area.
Command-N opens the catalog step while empty.

The card holds at most two rows. The notification row reports the macOS
permission. It offers "Turn on" to request permission while macOS holds no
decision. For a stored refusal, "Turn on" opens Paguro’s own notification page
in System Settings. The enabled state reads "On". The island row appears
only on a display with a camera housing, with a switch for the island route.
A permission that Paguro has not read yet shows no notification row, because
the state would change under the user. The card is left out when neither row
applies.

The two setup decisions have no other place at first run. Settings owns them
once the first service exists. The screen is the only first-run offer: Paguro
has no separate welcome sheet.

The import action reads a configuration file and adds it. The Settings import
offers an Add or Replace choice; this screen has nothing to replace, so it adds
the file and reports the result. See [Configuration transfer](CONFIGURATION.md).

The whole glass background moves the window, the way the reserved gap in the
top bar does. The traffic lights stay visible and uncovered. The menu bar keeps
every command: Add Service (`Command-N`), Settings, and import all work while
the screen is up. The quick switcher opens and finds nothing.

Moving between setup pages uses a 0.22-second fade and 24 points of horizontal
travel. Forward enters from the right; Back enters from the left. Custom website
entry uses the native sheet transition. Reduce Motion uses a fade with no
travel for the wizard pages. Card selection fades its checkmark and border
over 0.14 seconds.

The saved selection ends the wizard. The shell fades in over 0.3 seconds and the
rail slides in from the edge it lives on. Reduce Motion keeps the fade alone.
`PaguroMotion.firstRunSwapSeconds` holds the duration. `AppState.addSetupServices`
selects the first chosen service, so the shell opens on it.

App Lock wins. A locked launch shows the lock screen, and the welcome screen
waits under it. None of its actions can run while the window is locked, so the
import line is closed to a click and to a keyboard activation. The import
itself refuses a locked app as well. The catalog and batch save also refuse a
locked app. Lock disables the custom website sheet and cancels pending icon discovery.

Keyboard focus starts on **Choose your services**. The catalog starts focus in
search after the page enters the focus hierarchy. The category menu does not
take focus when the page appears. Tab reaches the workspace name, search,
category menu, Custom website, service grid, and footer buttons. These controls participate even when macOS
limits its usual Tab navigation to text inputs. Shift-Tab reverses the order.
The category menu uses a native popup with direct choices and keyboard handling.

The grid is one Tab stop. Arrow keys move a visible focus outline between cards;
Space or Return toggles the focused card. The outline differs from a selected
card's checkmark and accent border. Clicking a card hides the dotted outline
while keeping it ready for keyboard input. Tab entry, arrow movement, and
Space or Return restore the outline. Moving focus scrolls the card into view.
`SetupGridNavigation` in PaguroCore follows the current column count and keeps
custom and catalog sections on separate rows. Filters retain a visible target
or choose the first result; empty results have no card target.

Down Arrow or Return from search enters the results. Return does not create a
workspace while browsing cards. Command-Return creates the workspace, or Tab to
Create workspace and press Space or Return. Command-Shift-N opens custom entry.
Dismissing custom entry restores its opener's focus. Adding a custom website
returns focus to its new card after the sheet closes. The sheet cannot create
the workspace through the underlying Command-Return shortcut.

Clicking the background releases text-field focus. Clicking a service moves
focus to the grid. Return finishes editing the workspace name. Window dragging
still works after ending text editing. VoiceOver reads each card's name and
selection state and keeps its select action.

On the welcome step, VoiceOver reads the title, explanation, setup rows, import
action, and primary button in that order. A row is one element with its title
and description. Its control stays a separate element beside it. Increase Contrast gives the
card a full border, and Reduce Transparency gives it an opaque background.

### Debug preview

Debug builds accept `--paguro-first-run-preview`. The **Paguro First Run Preview**
scheme starts with no workspace or service on every run. Its account graph and
WebKit sessions stay in memory. Adding a service or importing a configuration
shows only that run's services and ends the welcome screen. Quitting discards
those test services and sign-ins. The normal **Paguro** scheme uses the saved setup.

The preview bypasses normal-store restore, snapshots, and recovery history.
It uses separate recovery defaults and disables persistent-session enumeration,
so the empty test graph cannot reclaim the normal app's sign-in data. macOS
notification authorization remains the system decision for the Debug app.

`FirstRunPreviewConfiguration` sits completely inside `#if DEBUG`, so a Release
build compiles nothing from it. The release script and the direct build check
scan each built Release app for the argument and stop the build when it appears.

## Window structure

The sidebar layout has three parts:

1. A sidebar or icon dock.
2. A content header.
3. The active web view.

The top-bar layout remains available as a separate user choice.

## Sidebar states

The expanded material surface is 218 points wide.
An 8 point window gutter surrounds it, so the complete rail is 234 points wide.
It shows the current workspace, service icons, service names, status marks, and the
add action.

The collapsed dock is 54 to 84 points wide.
It shows only service icons and live status marks.
Each service icon is 14 to 44 points square.
The default size is 22 points.
The selection area and rail width grow with this size.
It does not show the workspace selector or the add action.
Its material surface starts 52 points below the window top.
The first dock item starts 8 points below this edge.
The first dock item aligns with the web-page area.
The material surface keeps an 8 point gutter above the window bottom.
This position keeps the dock edge away from the traffic lights.

A rail with more items than it shows scrolls.
Both rail presentations hide the system scroll bar.
A legacy scroll bar takes its width from the rail content, which moves every
icon off the rail centerline as soon as the rail overflows.
The rail draws its own indicator instead: a 3 point capsule over the trailing
edge, 2 points from the rail surface.
The indicator is as long a part of the rail as the rail is of its content, and
it is 20 points long at least.
It appears while the rail scrolls and fades out after 0.9 seconds without
movement.
It takes no pointer event, so the rail keeps every hover, click, and context
menu.
`RailScrollIndicator` in PaguroCore holds its length and its position.
The workspace rail follows the same rule.
The top bar hides its own scroll bar already: a horizontal scroll bar takes
height, and the bar keeps one height in every state.

The selected service, drag order, badge count, health state, media state,
keyboard focus, context menu, tooltip, and VoiceOver label remain available in
both states.
Manual global mute adds a barred bell to every visible service in both states.
It does not hide unread badges.
A service that keeps playing audio after a switch shows a speaker mark in both
states. A muted service never shows it, because mute ends that state.
The mark therefore takes the place of the barred bell on a collapsed icon and on
an icon-only tab. The unread badge keeps the trailing corner.
An expanded row draws the mark beside the call mark, before the hibernation,
mute, and unread marks.
The mark changes no row height and no icon position. It takes no pointer event,
so the rail keeps one fixed mouse surface and its magnification.
Increase Contrast and Reduce Transparency make the expanded mark the primary
text color.
The collapsed barred bell has no background tile. It uses a small contrast
shadow over the service icon.
An expanded service row uses a neutral hover fill. The fill remains quieter
than the selected service fill. A top-bar tab uses a lighter hover fill in dark
appearance, because the material behind the bar is a lighter ground than the
rail canvas. The selected fill is the same in both rails.

The Icon Rail settings shape the collapsed rail on the left, whether it holds
the services or the workspaces. Paguro hides that settings section while the
layout is the bar along the top, which has no rail for them to shape.

In the icons-only top bar, a hovered tab shows its name under the bar. The bar
draws this tooltip, not the tab, so the scrolling tab strip cannot cut it off.

The top bar is as tall as the content header of the sidebar layout, so the
window keeps one top edge in both. Eight points separate two tabs. A top-bar
tab uses a 16 point icon, and 18 points when it shows no name. Both stay under
the 18 point sidebar icon, because one bar holds every service of every open
workspace.
The workspace control in the bar takes the width of its own name, up to 150
points. A longer name truncates there rather than push the tabs sideways.

## Layouts

Four layouts arrange the shell:

- Rail on the left. One rail holds the workspaces and the services.
- Bar along the top. One bar holds both.
- Workspaces left, services on top.
- Services left, workspaces on top.

A rail down the left owns the complete left column, in a two-rail layout as
much as in the sidebar layout. The bar starts at the rail's trailing edge, so
collapsing the rail widens the bar with the content under it. The collapse
control remains the single travelling control at the rail's moving edge.

Beside an expanded rail the bar starts at the rail edge. Beside a collapsed
rail the bar clears the window controls that the narrower rail leaves
uncovered.

The workspace rail follows the service rail: the same widths, the same two
presentations, the same surface, the same reorder-free cells. It holds one
workspace for each cell and an add control at its foot. The workspace bar holds
one chip for each workspace, and the chips keep their names.

Every workspace shows its unread total, except the current one. Its services
are all in the other rail with badges of their own.

The collapsed workspace rail shows a gray folder for a workspace with no emoji,
because an icon-only cell would otherwise be empty. Every other place keeps a
workspace with no emoji as its name alone.

The retired `hybrid` layout value maps onto Workspaces left, services on top,
which is the layout it named.

The Workspace view setting controls the two one-rail layouts. A two-rail layout
shows every workspace already, so Paguro hides the setting there.
Current workspace keeps the workspace palette model.
All workspaces is the default and shows an accordion section for each workspace
in the expanded sidebar. Sections start expanded. Users can collapse them for
the current window session. A collapsed section shows the aggregate badge.
Visible service rows show unread status while users keep a section expanded.
An 8 point gap separates adjacent workspace sections. Each disclosure chevron
aligns with the service icon column.
A workspace opens on the service it was last left on. A workspace with nothing
recorded, or one whose recorded service has since left it, opens its first
service. A service named together with a workspace wins over both. The quick
switcher and the menu bar name the two together. Paguro keeps the record
outside the model store, as a window state. It drops the record of a workspace
that is deleted.

Selecting a service selects its workspace. Arrow navigation and drag reorder
stay within that workspace. Moving a service between workspaces remains an
explicit context-menu action. A workspace section menu can add a service to
that workspace, including when the workspace is empty. The same menu can mute
the workspace.
When more than one workspace exists, the Add Service dialog shows a Workspace
menu for catalog and custom services. It starts with the workspace that opened
the dialog. The chosen workspace receives the new service and becomes active.
The dialog hides this menu when only one workspace exists.
The workspace editor can leave the emoji empty. Paguro then shows the workspace
name without a replacement symbol or leading space. The collapsed workspace
rail is the one exception, because it has no name to show.

Removing a service from a workspace keeps the service when it is also in
another workspace. When that workspace was its last one, Paguro saves the
change and then deletes the service and its sign-in data.
Deleting a workspace asks for confirmation. The message states how many
services exist only in that workspace. Paguro deletes those services and their
sign-in data with the workspace. Services that are also in other workspaces
stay available. The rail and the workspace editor show the same message.
Return or Space opens the service that has keyboard focus.

`Control-Command-S` expands or collapses the sidebar.

In the collapsed All workspaces view, all non-empty workspace groups remain
visible. A horizontal divider with 15 point side padding separates adjacent
groups.
Section disclosure state does not hide a group from the icon dock. If one
service appears in several workspaces, its tooltip and VoiceOver name include
the workspace.

The service editor can set a custom icon from a local image or a website.
See [Service icons](SERVICE-ICONS.md).

The Icon Rail settings follow the macOS Dock control model.
The Size slider controls the base icon size.
The Magnification slider controls the complete effect.
Zero turns magnification off. Higher values increase the peak size smoothly.
The nearest two icons on each side receive a smaller part of the effect.
Affected rows grow to move neighboring icons apart.
The hovered icon keeps its original vertical center. Icons above it move up,
and icons below it move down.
Icons grow toward the right and can extend over the web content edge.
Paguro hides dock selection and hover tiles while magnification is active.
Hovering an icon shows its service name in a material label on the right.
The label keeps a 12 point gap after the rail or the magnified icon.
It uses the current Window glass preset.
It does not take pointer events or replace the VoiceOver service name.
Hover entry is immediate. Hover exit has a short delay so a changing pointer
target does not make the icon and label flicker.
Adjacent icon hover targets fill their rows and meet without a dead area.
Reduce Motion keeps the size change and removes its animation.
The Vertical position setting offers Top and Center.
Top is the default. Center aligns the base-size stack with the complete app
window's vertical centerline, not the shortened dock viewport's centerline.
The icon viewport ends at the inner top and bottom edges of the dock surface.
It clips vertical overflow and permits vertical scrolling when items do not fit.
It keeps horizontal overflow visible for magnification and tooltips.
Icon sizes follow the pointer position along the rail, on a continuous curve
that is level at both of its ends. A pointer move carries no animation. The
effect fades in when the pointer enters the rail and out when it leaves, so an
icon never appears at its magnified size.

Each cell reads the pointer itself, so a mouse move re-renders the cells rather
than the rail and its fetches. The cells lay out at their resting size and draw
the effect as a scale and a move. A mouse move then measures no layout at all.

A magnified icon reaches past the rail. The rail chooses the hovered item. A
cell reports only whether the pointer remains on horizontal overflow. This
report holds the effect and its last position until the pointer leaves.

A cell moves in the drawing alone. One fixed spatial pointer surface covers the
rail viewport. A pointer event resolves the item from the drawn stack once,
when the event arrives. The resolver does not change a hit shape. Keyboard and
VoiceOver activation keep the cell's semantic identity. A cell forwards only a
click on horizontal icon overflow that lies outside the rail surface.
The rise that keeps the point under the pointer in place stops at the room the
rail has above its stack. A top-aligned rail at rest has none, so its first icon
grows downward from a fixed top edge rather than up into the clip. The drawing
then parts from the resting stack. The rail surface receives visible spill
above and below the stack without changing layout or scroll distance. Workspace
dividers use the same event route. A bare divider selects nothing.
A collapsed tooltip follows the visible icon edge and stands one gap after it.
The edge of the drawn rail surface is its floor, not the rail frame. A small
icon then keeps the tooltip beside the rail rather than an inset away from it.

The main window holds a minimum content width of 800 points. A drag of the
window edge stops there, so the shell cannot overlap its own content. The
window has no minimum height: a short window compresses the rail and the web
content instead.

Paguro saves the main-window sidebar state and restores it after a new launch.
Use the sidebar button or `Command-Control-S` to change the state.

When exactly one workspace exists, the rail does not show its name or switcher.
The top bar still keeps service tabs clear of the traffic lights.

In All workspaces mode, the top bar groups its tabs by workspace. Each group
starts with the workspace name, and a divider separates adjacent groups. A
click on a name opens that workspace. The bar hides the current-workspace
control while it groups, because each name already says which workspace its
tabs belong to.

The Show icons only setting appears where the services are in the bar, in both
workspace views. It removes the service names from the tabs. Workspace names stay in
both workspace views. Tooltips and VoiceOver labels keep every service name
available. A stored icons-only value never reaches the sidebar, because
`RailBarPresentationPolicy` resolves it against the current layout.
The File menu can add a workspace.
A secondary click on the sidebar background can add a service or workspace.
Service rows keep their own context menus.
The service context menu opens the live page in the user's default browser.
While a service keeps playing audio, the same menu offers Pause Audio. It stops
that audio and ends the exemption. A click on the service in the rail is the
route back to it.
The menu names this action Open in Browser, because Paguro asks the system for
the default browser and does not choose Safari.

## Service reorder

A service moves inside its workspace like an icon in the macOS Dock.
Press a service and move the pointer 6 points to start the reorder.
A shorter movement stays a click and opens the service.

The pressed cell follows the pointer along the rail axis only.
It grows a small amount, takes a shadow, and draws above its neighbors.
The other cells move away and open a space at the target position.
The rail applies each step after the pointer passes one half of the cell pitch.
The cell pitch adds the gap of that rail to the cell length.
Release the pointer to save the new order.
The cell then settles into its space.

The same drag works in all three arrangements:
the expanded sidebar rows, the collapsed icon dock, and the top bar of tabs.
It moves a workspace as well, in every rail that shows more than one. Those are
the workspace rail, the workspace bar, the all-workspaces sidebar, and the
grouped top bar. `ServiceReorder` answers for services and workspaces alike.

A workspace drag folds the services away while it lasts. The sidebar folds its
sections and the grouped bar folds its tabs. Each is then one workspace name
after another. Everything returns on release. A release that ends a drag
neither folds a section nor opens a workspace.
The rail holds icon magnification during a drag, so the cell pitch keeps one
measure.
Reorder stays inside one workspace. The service context menu moves a service to
another workspace.

The vertical rail scrolls when it holds more services than its viewport shows.
A drag that holds the pointer within 28 points of the top or bottom edge scrolls
the rail. The speed increases near the edge.
The top bar shows a plain row of tabs and scrolls only when the tabs do not fit.
That fallback does not scroll during a drag.

The `Move up` and `Move down` VoiceOver actions and `Option` with an arrow key
give the same order change without a pointer.

## Content header

The content header is 52 points high.
It shows the active service name on the leading edge.
The trailing edge holds the service controls in this order:

1. The download indicator.
2. Back.
3. Forward.
4. Reload.
5. Global notification mute.

Each control uses its own circular Liquid Glass surface. Their hover fills use
the same circular shape.
The global notification mute suppresses new notification banners. It keeps
unread badges visible and adds a barred bell to each visible workspace header
and service.
Web appearance stays in the service editor because websites can ignore or
override the browser preference.

### Floating notices

The backup offer, offline status, microphone feedback, capacity notice, and
passkey notice use floating cards. The store error keeps its full-width strip.
`ContentView` owns the host above both the shell and first-run screen, below
the lock overlay. Cards take clicks only inside their frames and do not move
content or take keyboard focus. Locked windows suppress their announcements.

A card holds a symbol, title, optional explanation, up to two action buttons,
and a close button. A drag to the right has the same action as the close button.
The backup offer keeps Review backups and Not now, with no timer. Dismissal
means Not now. Offline stays until the connection returns or the user dismisses
it. A new connection loss raises it again. Microphone feedback lasts two
seconds. Capacity and passkey notices last 12 seconds. The passkey card has one
app-wide identity. Switching services neither restarts its timer nor removes it.

The stack shows at most three cards, newest first, with persistent cards taking
places before transient cards. Remaining cards wait for a free place. Paguro
shows the passkey notice once for the app and saves its seen state when raised.
Later services and launches do not repeat it. A stored seen flag from any older
service also counts as seen. The Debug preview uses its own resettable defaults.
A locked window cannot consume the notice. The Add Service sheet does not repeat it.

`FloatingNoticeCard` draws one card and `FloatingNoticeStack` places the stack.
`FloatingNoticeLayout`, `FloatingNoticeStackRule`, and `OfflineNoticeState` in
PaguroCore hold the layout, visible-card selection, and offline dismissal rules.
Cards clear the header and find bar; on the welcome screen they clear the
traffic lights. The card uses `NotificationIslandSwipeRule` for its drag.
See [Design choices](../DESIGN.md) for glass and accessibility rules.

### Page history

Back and forward move inside the page history of the active service.
Paguro reads `canGoBack` and `canGoForward` from the web view.
A control without a target stays in place and dims.
The View menu repeats both actions as `Command-[` and `Command-]`.
The service page keeps its own home action, and Paguro does not repeat it.

### Download indicator

The download indicator is the one global control in the content header.
It reports the downloads of every service, the way a browser download center
does. A switch of service therefore hides no running transfer and empties no
history. The ring, the badge, the count, and the list stay as they are.
Each record still names the service that started it.

The indicator appears when the app has one download record.
It stays in the header until the user removes the last record.
No record disappears on its own, so the route to a finished file remains
available after the transfer ends.

The control draws the Paguro download mark from the `DownloadIcon` asset.
The mark is a tray with an arrow above it.
The asset is a template image, so the mark follows the control color.
It is 15 points wide, which matches the system symbols beside it.

The control carries a small badge with the number of new downloads.
The badge counts the running downloads and the results the user has not seen.
Three transfers at one time therefore show `3` before any of them ends.
It prints `9+` above nine, so it stays narrow on a 28 point control.
The count takes the readable text size that the whole app uses, and the capsule
around it follows that size.
The badge uses the accent color, not the unread red, because a download does
not wait for a reply.

A result stops counting after 12 seconds, or when the user opens the list.
The earlier of the two events applies.
Opening the list marks every result in it as seen, in every service, because the
list shows every service.
A download that is still running keeps its unseen state, because the user
cannot have seen a result that has not happened.

The badge is short-lived feedback, not a list to empty.
When it reaches zero, the control stays in the header without it.
The record itself remains, so the route back to the file remains.

A download shows a progress ring only after it runs for 500 milliseconds.
Most downloads end sooner. A ring for such a download would appear and
disappear inside one or two frames, which reads as a flicker.
A fast download therefore moves from hidden to the resting mark and its badge.
The badge is the signal that a fast download arrived.

A young download does not replace a mark that the header already shows.
It keeps the earlier resting or failed mark until it earns its ring.
A young download with no earlier record shows nothing at all.

The ring is 24 points across, so it clears the corners of the mark and stays
inside the 28 point control.
A download without a reported size shows a turning arc instead of a value.
A still track would read as a stalled transfer.
The indicator rests as the plain mark when no download shows a ring.
A failed record uses the system exclamation mark instead, so a failure never
looks the same as a group of successful downloads. This difference does not
depend on color.

### Download indicator motion

The control grows from 85 percent with a fade when it enters the header.
A completed ring reaches its end, pulses one time to 112 percent, and settles
on the resting mark.
Reduce Motion replaces all three of these movements with an opacity change.
It removes the turning arc, the growth, and the pulse.

### The mark that reports a download start

A download mark appears over the web content when a download starts, and it
travels up into the header download control.
The mark makes the start visible without a notice that the user must read or
dismiss.

The mark starts on the vertical line of the control, 42 percent down the web
content, so it travels straight up.
It reads the frame of the control and the frame of the web content from the
views that own them. No value in this movement is a fixed position.
The mark is as large as the control it lands on, and it draws the same
`DownloadIcon` mark. The landing therefore reads as one object arriving.
It follows the shell glass rules of the floating notice card.
macOS 26 uses Liquid Glass, and an earlier system uses the material surface.
Reduce Transparency uses an opaque window background, and Increase Contrast adds
a visible border.

The movement has three parts and lasts 560 milliseconds in total:

1. A fade and a growth from 72 percent at the start place, over 120
   milliseconds.
2. A rise on an ease-in curve, over 440 milliseconds.
3. A shrink to 55 percent and a fade, inside the last 240 milliseconds of that
   rise.

The control then plays its own movement, so one handoff ends in the header.
The complete flight is longer than the 500 millisecond ring delay on purpose.
The first download of a service has no control in the header until that delay
passes. A shorter flight would land on an empty header.
A control that entered the header inside the last 260 milliseconds keeps its
entry growth and plays no pulse. That growth is the landing.

The mark takes no pointer input and no keyboard focus, and it holds no
accessibility element.
The page below keeps every click and every key while a download starts.
Paguro announces the start for VoiceOver as `Download started: <file name>`,
one announcement for each mark.
The control keeps its own label, so nothing is announced twice.

Several starts in one moment stay understandable:

- A start inside 300 milliseconds of a mark joins that mark, so ten files at
  one time send one mark.
- A later start sends its own mark, and two marks never leave closer together
  than 400 milliseconds.
- Three marks can be on the way at one time. A further start sends none.

The header badge counts every download, so a start that sends no mark is still
reported.
`DownloadFlightPlanner` in `PaguroCore` holds this rule, and
`DownloadIndicatorMotion` holds every number of the movement.
`DownloadFlightState` keeps the marks that are on the way and reports each
landing to the control.

Reduce Motion removes the travel. A short fade at the control reports the start
instead, and a group of starts still produces one fade.

A download that starts in a service that the window does not show sends no mark.
The control is global, so that start still has to reach the header.
A mark would rise out of a page that did not start the download.
The short fade at the control reports it instead, the cue that Reduce Motion
uses.

A download that starts while the main window is closed reports nothing, because
the overlay that draws the marks exists with that window. A window that shows no
service page reports nothing either: the mark has no place to leave from.

`DownloadStartCue.resolve` in `PaguroCore` holds this rule.
It reads the selected service, the service of the start, Reduce Motion, and
whether the window shows a service page.
It answers with the travel, the fade at the control, or nothing.

The mark crosses the area that holds the find bar and the floating notice
cards. It draws above them for a moment, it changes no layout, and it takes no
input from either of them.

The overlay that draws the marks sits at the window root, above the rails and
the web content together. The mark therefore crosses from the page into the
header in every rail layout. The bar layouts keep the control in the top bar,
and the mark travels to it there.

A finished download never opens the list. The user opens it with a click.

Clicking the indicator opens the download list.
The list holds the downloads of every service, newest first.
It names each download and reports its state.

Each line names its source on its secondary line.
The source is the saved icon of the service and the service name, and it comes
before the state of the transfer.
The line reads the icon through the same resolution as the rail and the
notification attachment, so one service cannot show two icons.
The name is the one that applied when the download began, so a record stays
readable after a rename or a deletion. A service that left the workspace keeps
that name with a generic mark, because it has no icon left.
A download that Paguro cannot attribute to a service shows no source.

A secondary click on a line offers `Go to <service>`, which shows that service.
The action uses the same selection route as the rail.
A record of a service that left the workspace offers nothing.

Clicking a finished line shows its file in the Finder.
That line draws a quiet hover fill, so the user can see the action.
Its tooltip and VoiceOver label both name the file and the Finder.
The action keeps the record, because the user can need that route again.

A running line and a failed line have no line action.
A running line has no file yet, and a failed line has none at all.
Neither line draws the hover fill, so a line without a target never looks
clickable.

Each line keeps its own trailing control beside the line action.
A running download has a stop control.
An ended download has a dismiss control.
The two controls never share a hit area with the line action.
Keyboard focus reaches the line action before its dismiss control.
Clear All removes every ended record at one time.
It sits under a separator at the bottom of the list and reads as a menu item.
The pointer, keyboard focus, and a press give it the accent highlight with
white text.

The VoiceOver label of the indicator always reports the number of records.
It adds the completed percentage during a download.

Records exist for the current app run only. `Command-Q` removes them.

See [Web sessions](WEB-SESSIONS.md) for the download destination rules.

One persistent sidebar button moves with the sidebar edge.
It rests at the trailing edge of the expanded sidebar.
The button rests at the start of the content header after the dock collapses.
The app must not replace the button during this movement.
The app adds the collapsed circular surface after this movement completes.
The collapsed header keeps a 16 point gap after the traffic-light group.

## Materials

Native behind-window surfaces cover the complete window.
These surfaces include the title bar and all safe-area insets.
The AppKit content view contains four layers in this order:

1. The native backdrop frost layer.
2. The optional native Liquid Glass layer.
3. The protective color layer.
4. The SwiftUI shell and the web content.

The protective color layer is not a child of the glass view.
This separation prevents AppKit from treating an opaque color as vibrant
content.
The sidebar samples the desktop or the window below Paguro.
The expanded surface has an 8 point inset rounded border.
The collapsed surface keeps an 8 point gutter on its horizontal and bottom
edges.
The content column keeps an 8 point gutter on the right and bottom edges.
The top-bar layout also keeps an 8 point gutter on the browser's left edge.
The horizontal rail forms the upper part of the frame around the browser.
The horizontal rail has no bottom separator.
The header starts at the window top and uses the native 52 point centerline.
The header does not compress when the window becomes short.
The browser and sidebar scroll viewport use the remaining height.
The browser top aligns with the top edge of the collapsed dock.
The Paguro header is part of the shell and has no browser outline or corner mask.
The native web view is the browser surface.
Its host clips all four corners with a 14 point continuous radius.

Each service control uses its own native circular surface.
The Window glass selector has four presets and no separate transparency slider:

| Preset | Native material | Extra backdrop frost | Protective tint |
| --- | --- | --- | --- |
| Follow system | Untinted Regular glass | None | None |
| Off | No glass | None | Opaque |
| Clear | Clear glass | 35 percent | None |
| Regular | Regular glass | Full strength | 15 percent |

Follow system is the default for a fresh install. Native glass responds to the
system Liquid Glass appearance. Paguro does not copy the system slider value.
The same preset applies to toolbar controls, cards, the menu-bar surface, and
the expanded island. Accessibility appearance settings remain in effect.
Existing saved glass choices stay unchanged, but each choice now uses fixed
opacity and frost values. Loading preferences removes the old slider setting.
Configuration import accepts the legacy opacity field but uses the preset;
export writes the preset's opacity for compatibility with older versions.

The presets update the main window live. They do not change the Settings
window, system-owned surfaces, or web pages. Selecting Follow system restores
the default behavior, so there is no separate Reset Glass Lab action.
On macOS 15, the glass selector is unavailable and the shell uses a solid tint
over the native visual-effect fallback.
The sidebar button uses a 32 point target.
Paguro removes its permanent surface in the expanded state.
Paguro gives it a circular material, border, and hover fill in the collapsed
state.
The service list does not use strong glass because it contains dense text.
Off uses a solid source-list selection and a blue selected service name.
The glass presets use a translucent neutral selection with black text in
light appearance and white text in dark appearance. The fixed tint strength
controls the blend, so Regular retains more selection fill than Clear.
The same rule applies to expanded rows and collapsed dock items.
The web page stays on an opaque or quiet semantic background.
The opaque dark shell tint uses `#242125`. Presets change its opacity, not its
RGB values.

The lock screen uses this same window material and protective tint.
It hides the underlying shell without unloading service views. Hidden shell
content does not accept pointer input or appear in the accessibility tree.
Lock transitions do not fade service content through the glass.

`ShellPreferences` owns shell-setting load, normalization, and persistence.
Layout and appearance use the transactional app preferences row. Glass,
icon-rail, workspace-view, and sidebar-state settings use `UserDefaults` so
they remain available while Paguro repairs or restores the content store.

On a fresh install, Paguro creates no workspace and no
service, so the window opens on the first-run welcome screen. Paguro follows
the system appearance, uses the left rail, shows all workspaces, and appears in
both the Dock and menu bar. The Dock badge is on. The collapsed rail uses 22 point icons, 26 percent magnification, and a
top-aligned stack. Automatic cookie-banner acceptance is off. Existing saved
choices remain unchanged.

The expanded sidebar footer contains a native bordered add-service button.
The footer is 52 points high.
It places the button slightly above its center.

## Menu-bar window

The Paguro status item uses the native window presentation.
Its icon is the Paguro mark from the `MenuBarIcon` asset.
The asset is a template image, so macOS tints the icon for the current
menu-bar appearance.
The window shows the visible unread total and a global notification mute
control. Global mute does not hide the unread total. Workspace sections show
their services with the same icons, unread badges, mute marks, speaker marks,
and selected state as the main window.

Selecting a service opens the main window at that service. A bounded scrolling
area keeps a large service list inside the available screen. The list reports
the height of its rows, up to 380 points, because the window takes its own
height from its content. A short list makes a short window. The header groups
global mute, Lock, and Settings on the right, with matching circular surfaces.
Lock closes the menu and uses the same app-lock route as File > Lock Now. It
is hidden when App Lock is off or Paguro is already locked.
The app name and shell mark open the main window, including
when no services exist. The window has no footer. These routes remain available
in Menu bar only mode. The complete window follows the Window glass
preset. The content also follows the selected Paguro appearance.

The selected service uses a light fill and an accent-colored checkmark. In
light appearance, the fill is 55 percent white, or opaque white with Reduce
Transparency. Dark appearance uses a quieter light fill. Hover uses the
neutral row highlight; it does not replace the persistent selection mark.

See [Web appearance](WEB-APPEARANCE.md) for the service appearance control.

## Accessibility

File > Open Notifications (Command-Shift-O) opens island history with focus on
the newest card. Paguro must be active, unlocked, and have island alerts
enabled, a notched display, and nonempty history. Escape returns focus to the
previous Paguro window. Pointer exit does not close a keyboard-opened island.

Each icon-only service has a tooltip and a complete VoiceOver label.
The label includes unread, mute, hibernation, media, and health states when they
apply.
The label of a service that keeps playing audio says "playing audio", and that
service carries a named Pause Audio action. The action appears only while the
state applies, because a named action that does nothing is worse than none.

The first focusable service does not show a focus ring only because the window
opened. Tab or arrow-key navigation enables the ring when focus differs from
selection.

The rail overflow indicator uses a fade alone, so Reduce Motion removes nothing
from it. Its position follows the scroll position directly.
Increase Contrast and Reduce Transparency make it stronger against the rail.
VoiceOver skips the indicator, because the rail reports its items already.

The collapse action has a keyboard route and a VoiceOver label.
Reduce Motion removes the animated sidebar transition.
Reduce Motion keeps the service reorder and removes its lift and its spring.
Each cell then moves directly to its new position.

## Configuration transfer

Settings > General > Configuration transfers workspaces, services, and portable
preferences in one JSON file. Import previews the file and adds fresh accounts
alongside existing workspaces or replaces them after explicit selection.
See [Configuration transfer](CONFIGURATION.md).
