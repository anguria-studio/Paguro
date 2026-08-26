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
An expanded service row uses a visible neutral hover fill. The fill remains
quieter than the selected service fill.

The Workspace view setting controls the sidebar layout.
Current workspace keeps the workspace palette model.
All workspaces is the default and shows an accordion section for each workspace
in the expanded sidebar. Sections start expanded. Users can collapse them for
the current window session. A collapsed section shows the aggregate badge.
Visible service rows show unread status while users keep a section expanded.
An 8 point gap separates adjacent workspace sections. Each disclosure chevron
aligns with the service icon column.
Selecting a service selects its workspace. Arrow navigation and drag reorder
stay within that workspace. Moving a service between workspaces remains an
explicit context-menu action. A workspace section menu can add a service to
that workspace, including when the workspace is empty. The same menu can mute
the workspace.
The workspace editor can leave the emoji empty. Atoll then shows the workspace
name without a replacement symbol or leading space.

Removing a service from a workspace keeps the service when it is also in
another workspace. When that workspace was its last one, Atoll saves the
change and then deletes the service and its sign-in data.
Deleting a workspace asks for confirmation. The message states how many
services exist only in that workspace. Atoll deletes those services and their
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
Atoll hides dock selection and hover tiles while magnification is active.
Hovering an icon shows its service name in a material label on the right.
The label keeps a 12 point gap after the rail or the magnified icon.
It uses the current Window glass style and shell transparency tint.
It does not take pointer events or replace the VoiceOver service name.
Hover entry is immediate. Hover exit has a short delay so a changing pointer
target does not make the icon and label flicker.
Reduce Motion keeps the size change and removes its animation.
The Vertical position setting offers Top and Center.
Top is the default. Center centers the base-size stack in the available height.
The icon viewport ends at the inner top and bottom edges of the dock surface.
It clips vertical overflow and permits vertical scrolling when items do not fit.
It keeps horizontal overflow visible for magnification and tooltips.

The sidebar state belongs to the window scene.
Use the sidebar button or `Command-Control-S` to change the state.

When exactly one workspace exists, the rail does not show its name or switcher.
The top bar still keeps service tabs clear of the traffic lights.
The File menu can add a workspace.
A secondary click on the sidebar background can add a service or workspace.
Service rows keep their own context menus.

## Content header

The content header is 52 points high.
It shows the active service name and reload.
Reload and global notification mute use separate circular Liquid Glass
controls. Their hover fills use the same circular shape.
The global notification mute suppresses new notification banners. It keeps
unread badges visible and adds a barred bell to each visible workspace header
and service.
The service page owns back, forward, and home navigation.
Atoll does not repeat these controls in permanent window chrome.
Web appearance stays in the service editor because websites can ignore or
override the browser preference.

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
The sidebar samples the desktop or the window below Atoll.
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
The Atoll header is part of the shell and has no browser outline or corner mask.
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
Atoll removes its permanent surface in the expanded state.
Atoll gives it a circular material, border, and hover fill in the collapsed
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
At 100 percent, Atoll adds no protective tint.
The Reset Glass Lab action restores Regular glass and 100 percent transparency.

`ShellPreferences` owns shell-setting load, normalization, and persistence.
Layout and appearance use the transactional app preferences row. Glass,
icon-rail, and workspace-view settings use `UserDefaults` so they remain
available while Atoll repairs or restores the content store.

On a fresh install, Atoll follows the system appearance, uses the left rail,
shows all workspaces, and appears in both the Dock and menu bar. The Dock badge
is on. The collapsed rail uses 22 point icons, 26 percent magnification, and a
top-aligned stack. Automatic cookie-banner acceptance is off. Existing saved
choices remain unchanged.

The expanded sidebar footer contains a native bordered add-service button.
The footer is 52 points high.
It places the button slightly above its center.

See [Web appearance](WEB-APPEARANCE.md) for the service appearance control.

## Accessibility

Each icon-only service has a tooltip and a complete VoiceOver label.
The label includes unread, mute, hibernation, media, and health states when they
apply.

The collapse action has a keyboard route and a VoiceOver label.
Reduce Motion removes the animated sidebar transition.
