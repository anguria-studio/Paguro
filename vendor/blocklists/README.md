# Blocklist source snapshots

These are the source lists used to generate the bundled WebKit rules.
`manifest.json` records their origins, licenses, source and output checksums,
converter revision, and rule counts. The lists retain their upstream headers.

- HaGeZi Light: GPL-3.0; see [license](../../licenses/GPL-3.0.txt).
- Fanboy's Annoyance List: CC BY 3.0; see [license](../../licenses/CC-BY-3.0.txt).

`scripts/convert_blocklist.sh` converts these snapshots with SafariConverterLib
v4.3.0. It does not fetch new lists. It needs network access to fetch the converter.
The app reads the resulting JSON as data. Conversion changes the format from
Adblock filter syntax into WebKit rules, and omits unsupported filter features.

To refresh the lists, choose an immutable HaGeZi commit, download its Light
list, and download the current Fanboy list from the URL in the manifest.
Preserve both complete source files and their license headers. Run the converter,
update the manifest hashes, source URLs, retrieval date, and rule counts, and
run the app tests before committing the sources and outputs together.

The snapshots and conversion script are the source materials for the bundled
data. Include them in source releases. Binary distributions include the license
texts and third-party notices, which link to this source directory.
