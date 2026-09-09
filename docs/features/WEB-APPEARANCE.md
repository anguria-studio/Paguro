# Web appearance

Status: active

## Purpose

Paguro sends a native light or dark color-scheme signal to each web service.
Paguro does not recolor the web page.

## User control

Automatic is the default.
It follows the effective Paguro window appearance.
Therefore, a service starts dark when Paguro is dark.

The service editor also has Always Light and Always Dark overrides.
The content header does not show an appearance action.
A persistent header action would imply that Paguro can recolor every service,
but many services ignore or override the browser preference.

An editor change applies without a web-view rebuild or reload.
Paguro saves an explicit override with the service.

## Implementation

Paguro sets the `NSAppearance` of each `WKWebView`.
WebKit then updates the CSS `prefers-color-scheme` media query.
This is the same signal that a website receives from Safari.

Paguro does not inject a theme library.
Paguro does not add an invert filter or replace service colors.

## Limits

The website must support `prefers-color-scheme` for this control to change its
appearance.
Some services use only an account setting for their theme.
For these services, the user must change the theme inside the service.

Paguro does not modify or bypass the service's own account setting.

## Test rules

Tests must verify these conditions:

1. Automatic follows light and dark Paguro appearances.
2. Always Light stays light when Paguro is dark.
3. Always Dark stays dark when Paguro is light.
4. Old Dark Reader On values map to Always Dark.
5. Old Dark Reader Off and Auto values map to Automatic.
6. A live appearance change does not rebuild the web view.
