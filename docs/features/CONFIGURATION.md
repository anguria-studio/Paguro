# Configuration transfer

Status: active

## Purpose

Settings > General > Configuration exports and imports one JSON file.
Use it to recreate a setup on another Mac without copying login sessions.

## Export

Export includes workspace names, emoji, order, mute state, service membership,
and service order. A service shared by two workspaces remains one account.
It includes configured service URLs, names, custom icons, catalog references,
zoom, custom CSS, user agent, and appearance. Notification, media, background
presence, external-link, and hibernation settings also transfer.

App preferences include appearance, rail settings, Dock and menu-bar presence,
notification routes, and quiet hours. App-lock settings, content blocking, icon
fallback, media defaults, and hibernation defaults also transfer.

The file does not contain cookies, passwords, WebKit storage identifiers,
cache, browsing history, fetched icons, notification history, or unread counts.
It does not copy macOS permissions, launch at login, window placement, the
current selection, or temporary Do Not Disturb. The JSON is readable text and
contains configured URLs and custom CSS. It is not encrypted.

## Import

The file picker reads at most 20 MB. Core validates the format version, record
counts, identifiers, references, text sizes, URLs, and preference values before
any records change. URLs must use HTTP or HTTPS and have no embedded username
or password. The current format allows 100 workspaces and 500 services, icons
up to 1 MB each, and custom CSS up to 64 KB per service. The app validates and
normalizes custom icon images before it writes any records.

The preview lists workspace names and counts, with two import modes:

- Add to Current appends workspaces. Existing accounts stay unchanged. Importing
  the same file again adds another copy.
- Replace Current removes all current workspaces and services and imports the
  file in their place. The preview shows the current counts and explains that
  local login sessions will be removed. Replace and Import confirms this action.

Every imported account receives fresh service and WebKit storage identifiers
and starts signed out. IDs in the file only link its own records. They cannot
attach an imported account to an existing session.

The user can turn off Apply app preferences from this file. Service-specific
settings still come with the imported services. With the option on, app
preferences replace the current choices and runtime adapters reload them after
the save. App lock on launch applies at the next launch. macOS permission
requests remain under macOS control. No relaunch is needed for the import.

The workspace graph and optional SwiftData preferences save in one transaction.
A failed save rolls them back before runtime or UserDefaults changes begin.
Replacement removes old records in the same transaction as the import. After
commit, the app closes removed web views, clears their island history, repairs
selection, and schedules their local browser storage for removal.
Cancel and invalid files leave the setup unchanged. Export and import require
Blatta to be unlocked. Neither action transfers browser storage.

## Architecture

`ConfigurationArchive` and `ConfigurationArchiveCodec` in BlattaCore define the
versioned schema and validation. `WorkspaceStore` maps the model graph and owns
the import transaction. `PreferencesStore` stages only explicit portable fields
in that transaction. `ShellPreferences` maps the portable shell values.
`AppModel` connects persistence to runtime updates. `ConfigurationFileAccess`
owns the native panels and bounded file access. The Settings view owns the
preview and result message.

## Verification

Core tests cover JSON round trips, unsupported versions, invalid URLs and
values, oversized files, and duplicate or missing references. App tests cover
shared accounts, order, fresh sessions, existing accounts, repeated imports,
custom icons, preference transfer, shell reload, and failed-save rollback.
Replacement tests cover complete replacement, shared accounts, empty files,
cleanup identifiers, and restoration of the old graph after a failed save.

Manual check on two Macs:

1. Export from Settings > General > Configuration on the first Mac.
2. Transfer the JSON file to the other Mac and choose Import Configuration.
3. Choose Add to Current or Replace Current, then choose whether to apply app preferences.
4. Import. Check names, icons, order, mute state, and appearance.
5. Confirm imported services need sign-in. Add keeps existing accounts; Replace removes them.
6. Cancel another import and confirm the list does not change.

Local export, import preview, and Cancel passed on September 9.
The user confirmed replacement import works on September 9.
All 418 app tests and 228 Core tests passed. The test report did not identify
the destination Mac; the complete two-Mac checklist remains a follow-up.
