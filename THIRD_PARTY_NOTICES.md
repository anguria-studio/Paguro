# Third-party notices

Blatta contains work from other open-source projects.
Keep this file current when you add, remove, or update third-party work.

## Chorus

Blatta uses [Chorus](https://github.com/nicojan/Chorus) as its code base.

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
`scripts/convert_blocklist.sh` records the pinned source for each file.

### HaGeZi Light DNS blocklist

- Project: [HaGeZi DNS Blocklists](https://github.com/hagezi/dns-blocklists)
- License: GPL-3.0
- Source: `adblock/light.txt` at the tag pinned in `scripts/convert_blocklist.sh`
- Bundled file: `Blatta/Resources/hagezi-light.json`
- Use: source data for bundled WebKit content rules

### Fanboy's Annoyance List (EasyList)

- Project: [EasyList](https://easylist.to/)
- License: CC BY 3.0, as declared in the list header
- Source: `https://easylist-downloads.adblockplus.org/fanboy-annoyance.txt`
- Bundled file: `Blatta/Resources/fanboy-annoyance.json`
- Use: source data for bundled WebKit content rules

EasyList publishes this list as a moving file with no versioned download.
Record the fetch date in the commit message when you regenerate it.

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
The release audit must review each bundled mark.
