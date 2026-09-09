# Third-party notices

Blatta contains work from other open-source projects.
Keep this file current when you add, remove, or update third-party work.

## Chorus

Blatta is a fork of [Chorus](https://github.com/nicojan/Chorus) by Nico Jan.

- Copyright: 2026 Nico Jan
- License: MIT
- Use: application base, WebKit runtime, models, and tests

The `LICENSE` file contains the upstream MIT license and copyright notice.
Git keeps the upstream commit history.

## Bundled blocklist data

Blatta bundles two converted rule files under `Blatta/Resources`.
Each file keeps the license of the list it came from.
The Blatta MIT license does not cover either file.

Blatta reads these files as data at runtime.
It does not link them into the application.
[Source snapshots and manifest](vendor/blocklists/README.md) record the exact
inputs, conversion settings, and checksums. `scripts/convert_blocklist.sh`
converts those snapshots. Conversion changes Adblock filters to WebKit JSON
and omits unsupported filter features.

### HaGeZi Light DNS blocklist

- Project: [HaGeZi DNS Blocklists](https://github.com/hagezi/dns-blocklists)
- License: [GPL-3.0](licenses/GPL-3.0.txt)
- Source: `adblock/light.txt` at commit `2555e95206786ec3afea8c851729e64e74b093f5`
- Authors: HaGeZi and the list contributors
- Bundled file: `Blatta/Resources/hagezi-light.json`
- Use: source data for bundled WebKit content rules

### Fanboy's Annoyance List (EasyList)

- Project: [EasyList](https://easylist.to/)
- License: [CC BY 3.0](licenses/CC-BY-3.0.txt), as declared in the list header
- Authors: Fanboy and the EasyList contributors
- Source: `https://easylist-downloads.adblockplus.org/fanboy-annoyance.txt`
- Bundled file: `Blatta/Resources/fanboy-annoyance.json`
- Use: source data for bundled WebKit content rules

EasyList publishes this list as a moving file with no versioned download.
The repository preserves the September 9, 2026 source snapshot. Its header
identifies version `202609091502`. Record future refreshes in the manifest.

## SafariConverterLib

- Project: [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib)
- License: GPL-3.0
- Use: offline build tool only

Blatta does not link this tool into the application.

## The SVG project and service marks

- Project: [The SVG](https://github.com/GLINCKER/thesvg)
- Tool license: MIT
- Use: source for service identification icons

Service logos and names can be trademarks.
Their owners keep all trademark rights.
The [service-icon inventory](vendor/service-icons.json) records all 63 bundled
marks, their collection source URLs, and file checksums. They identify services;
they do not imply endorsement or affiliation. The collection tooling license
does not grant rights to third-party trademarks.

## Sparkle

- Project: [Sparkle](https://github.com/sparkle-project/Sparkle)
- Version: 2.9.6
- License: MIT and bundled component notices in [Sparkle license](licenses/Sparkle.txt)
- Use: signed updates in the direct-download build only

The framework includes its license in the distributed application.

## Blatta application icon

The app uses Blatta-specific Icon Composer artwork under `Blatta/AppIcon.icon`.
This artwork replaced the Chorus application icon. Its vector layers and edit
history are in this repository.

## Distribution of notices and data sources

The app bundle includes `LICENSE`, this notice file, and the `licenses` folder
in `Contents/Resources`. Sparkle also includes its own bundled notices.
Source materials for the converted blocklists are in
[the Blatta source repository](https://github.com/anguria-studio/Blatta/tree/main/vendor/blocklists).
Use the source tag matching the binary release to retrieve its exact snapshots
and conversion script. GitHub source archives include these materials.
