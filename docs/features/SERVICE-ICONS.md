# Service icons

Status: active

## User behavior

Each service has one icon across the sidebar, collapsed rail, top bar, quick
switcher, menu-bar list, and native notification attachment.

The main icon in a macOS notification is always the Atoll app icon. macOS uses
that icon to identify the sending application. Atoll supplies the service icon
as an additional image.

The custom-service form and the service editor show an icon preview.
The user can choose a local image or enter a website or direct image address.
A blank icon address uses the service address.
An address without a scheme uses HTTPS.

Use Default removes the custom icon.
It does not remove a bundled catalog icon or the icon that Atoll fetched from
the service address.

## Resolution order

Atoll uses the first available source in this order:

1. The custom image selected or fetched by the user.
2. The bundled icon for a catalog service.
3. The icon fetched automatically from the service website.
4. A colored tile with the first letter of the service name.

## Website discovery

Atoll accepts a direct HTTP or HTTPS image address.
For a website address, Atoll checks these sources:

- common `apple-touch-icon` and favicon paths;
- HTML `link` elements with `icon` or `apple-touch-icon` relations;
- the `icons` array in a linked web-app manifest;
- the optional Google favicon fallback when the user enables it.

Atoll prefers larger declared images.
It does not use a monochrome-only manifest image as a full-color service icon.

## Storage and limits

Atoll stores the selected image with the service.
It does not depend on the source address after the fetch succeeds.
Atoll discards the source address after the fetch.
`WorkspaceStore` saves custom icons and automatic favicon attempts. A failed
automatic fetch keeps the older icon and records the attempt time.

Choose a local source image no larger than 20 MB.
Atoll converts it to PNG and limits its longest edge to 256 pixels.
Each network response has a 5 MB limit.

The fetcher accepts only image formats that it can validate and decode.
It limits manifest and icon candidates from untrusted pages.
Parsed icon and manifest links must use HTTP or HTTPS and must not target a
loopback, link-local, or private host.
