# Native shell

Status: active

## Purpose

The native shell gives each web service a consistent Mac interface.
It does not change the web content of a service.

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

The selected service, drag order, badge count, health state, media state,
keyboard focus, context menu, tooltip, and VoiceOver label remain available in
both states.
Manual global mute adds a barred bell to every visible service in both states.
It does not hide unread badges.
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
It uses the current Window glass style and shell transparency tint.
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

### Page history

Back and forward move inside the page history of the active service.
Paguro reads `canGoBack` and `canGoForward` from the web view.
A control without a target stays in place and dims.
The View menu repeats both actions as `Command-[` and `Command-]`.
The service page keeps its own home action, and Paguro does not repeat it.

### Download indicator

The download indicator appears when the service has one download record.
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
The badge uses the accent color, not the unread red, because a download does
not wait for a reply.

A result stops counting after 12 seconds, or when the user opens the list.
The earlier of the two events applies.
Opening the list marks every result in it as seen.
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

A finished download never opens the list. The user opens it with a click.

Clicking the indicator opens the download list.
The list names each download and reports its state.

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

Each service control uses its own native circular Liquid Glass surface.
The experimental Glass Lab controls the main window materials.
The Window glass selector has Off, Clear, and Regular values.
The shell transparency slider controls the protective tint.
The native visual-effect view uses full strength for Regular and Off. It uses
70 percent strength for Clear.
The shell controls update the main window live.
They do not change the Settings window, system-owned surfaces, or web pages.
The sidebar button uses a 32 point target.
Paguro removes its permanent surface in the expanded state.
Paguro gives it a circular material, border, and hover fill in the collapsed
state.
The service list does not use strong glass because it contains dense text.
At 60 percent shell transparency, the sidebar selection starts to change from
the solid source-list fill to a translucent neutral highlight.
The transition is continuous and reaches the adaptive highlight at 100 percent.
The same rule applies to expanded rows and collapsed dock items.
The expanded selected service name is blue below this boundary. From 60 percent
upward, it is black in light appearance and white in dark appearance. This rule
keeps contrast against the frosted highlight.
The web page stays on an opaque or quiet semantic background.
The opaque dark shell tint uses `#242125`.
The transparency slider changes its opacity and does not change its RGB values.
At 0 percent, the protective layer is opaque across the complete window.
At 100 percent, Paguro adds no protective tint.
The Reset Glass Lab action restores Regular glass and 100 percent transparency.

`ShellPreferences` owns shell-setting load, normalization, and persistence.
Layout and appearance use the transactional app preferences row. Glass,
icon-rail, workspace-view, and sidebar-state settings use `UserDefaults` so
they remain available while Paguro repairs or restores the content store.

On a fresh install, Paguro follows the system appearance, uses the left rail,
shows all workspaces, and appears in both the Dock and menu bar. The Dock badge
is on. The collapsed rail uses 22 point icons, 26 percent magnification, and a
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
their services with the same icons, unread badges, mute marks, and selected
state as the main window.

Selecting a service opens the main window at that service. A bounded scrolling
area keeps a large service list inside the available screen. The list reports
the height of its rows, up to 380 points, because the window takes its own
height from its content. A short list makes a short window. The header groups
global mute, Lock, and Settings on the right, with matching circular surfaces.
Lock closes the menu and uses the same app-lock route as File > Lock Now. It
is hidden when App Lock is off or Paguro is already locked.
The app name and shell mark open the main window, including
when no services exist. The window has no footer. These routes remain available
in Menu bar only mode. The complete window follows the Window glass and Shell
transparency settings. The content also follows the selected Paguro appearance.

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

The first focusable service does not show a focus ring only because the window
opened. Tab or arrow-key navigation enables the ring when focus differs from
selection.

The collapse action has a keyboard route and a VoiceOver label.
Reduce Motion removes the animated sidebar transition.
Reduce Motion keeps the service reorder and removes its lift and its spring.
Each cell then moves directly to its new position.

## Configuration transfer

Settings > General > Configuration transfers workspaces, services, and portable
preferences in one JSON file. Import previews the file and adds fresh accounts
alongside existing workspaces or replaces them after explicit selection.
See [Configuration transfer](CONFIGURATION.md).
