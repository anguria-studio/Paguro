# Service icons

Status: active

## User behavior

Each service has one icon across the sidebar, collapsed rail, top bar, quick
switcher, menu-bar list, and native notification attachment.

The main icon in a macOS notification is always the Paguro app icon. macOS uses
that icon to identify the sending application. Paguro supplies the service icon
as an additional image.

The custom-service form shows an icon preview beside the name and address.
It discovers the website icon after a 600 ms pause in address input.
Changing the address cancels the older request and clears its preview.
Closing the form cancels discovery. A late response cannot replace a newer
preview or a manually selected image.

Change Icon offers Choose Image and Use Website Icon. A missing website icon
keeps the initial-letter tile. Discovery never disables Add Service.
A completed preview is saved as an automatic website icon, with its fetch time.
If the user adds the service before discovery finishes, normal background
discovery starts for the saved service.

The service editor keeps the detailed website and direct-image address controls.
A blank icon address uses the service address. An address without a scheme uses
HTTPS.

Use Default removes the custom icon.
It does not remove a bundled catalog icon or the icon that Paguro fetched from
the service address.

## Resolution order

Paguro uses the first available source in this order:

1. The custom image selected or fetched by the user.
2. The bundled icon for a catalog service.
3. The icon fetched automatically from the service website.
4. A colored tile with the first letter of the service name.

The Browse catalog also shows bundled icons before fetched website icons.
Notification Test includes the Paguro icon, so it is available before a fetch.
Its bundled light and dark variants follow the shell appearance.
In service rows, the complete Paguro tile has a 10 percent optical size
adjustment to balance the surrounding flat logos. The shell and square scale
together. Custom icons keep their original sizing.

## Website discovery

Paguro accepts a direct HTTP or HTTPS image address.
For a website address, Paguro checks these sources:

- HTML `link` elements with `icon`, `apple-touch-icon`, or
  `apple-touch-icon-precomposed` relations;
- the `icons` array in a linked web-app manifest;
- common `apple-touch-icon` and favicon paths, when page discovery fails;
- the optional Google favicon fallback in non-Store builds when enabled.

The App Store build excludes the Google request path and its Settings control.
Saved and imported opt-in values cannot enable it. The portable configuration
field remains compatible with other builds. Direct website discovery and the
initial-letter fallback remain available.

Paguro prefers larger declared images.
Page-declared images take precedence over conventional root filenames.
This preserves page-specific branding on websites that host several products.
It does not use a monochrome-only manifest image as a full-color service icon.

## Storage and limits

Paguro stores the selected image with the service.
It does not depend on the source address after the fetch succeeds.
Paguro discards the source address after the fetch.
`WorkspaceStore` saves custom icons and automatic favicon attempts. A failed
automatic fetch keeps the older icon and records the attempt time.

Choose a local source image no larger than 20 MB.
Paguro converts it to PNG and limits its longest edge to 256 pixels.
Each network response has a 5 MB limit.

The fetcher accepts only image formats that it can validate and decode.
It limits manifest and icon candidates from untrusted pages.
Parsed icon and manifest links must use HTTP or HTTPS and must not target a
loopback, link-local, or private host.
