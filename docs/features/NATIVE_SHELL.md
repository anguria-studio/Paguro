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
It shows the current space, service icons, service names, status marks, and the
add action.

The collapsed dock is 54 to 84 points wide.
It shows only service icons and live status marks.
Each service icon is 14 to 44 points square.
The default size is 24 points.
The selection area and rail width grow with this size.
It does not show the space selector or the add action.
Its material surface starts 52 points below the window top.
The first dock item starts 8 points below this edge.
The first dock item aligns with the web-page area.
The material surface keeps an 8 point gutter above the window bottom.
This position keeps the dock edge away from the traffic lights.

The selected service, drag order, badge count, health state, media state,
keyboard focus, context menu, tooltip, and VoiceOver label remain available in
both states.

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
The label keeps a 14 point gap after the rail or the magnified icon.
It does not take pointer events or replace the VoiceOver service name.
Hover entry is immediate. Hover exit has a short delay so a changing pointer
target does not make the icon and label flicker.
Reduce Motion keeps the size change and removes its animation.
The Vertical position setting offers Top and Center.
Center is the default and centers the base-size stack in the available height.
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

The service-control group uses native Liquid Glass.
The experimental Glass Lab controls the main window materials.
The Window glass selector has Off, Clear, and Regular values.
The shell transparency slider controls the protective tint.
The native visual-effect view stays at full strength to obscure background
detail.
Both controls update the main window live.
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
The web page stays on an opaque or quiet semantic background.
The opaque dark shell tint uses `#242125`.
The transparency slider changes its opacity and does not change its RGB values.
At 0 percent, the protective layer is opaque across the complete window.
At 100 percent, Atoll adds no protective tint.
The Reset Glass Lab action restores Clear glass and 50 percent transparency.

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
