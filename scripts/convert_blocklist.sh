#!/usr/bin/env bash
#
# Regenerates the bundled content-blocking lists from pinned upstream sources,
# using AdGuard's SafariConverterLib to convert filter lists into the
# WKContentRuleList JSON the app compiles at launch:
#   - Blatta/Resources/hagezi-light.json   (HaGezi "Light" ad/tracker domains)
#   - Blatta/Resources/fanboy-annoyance.json (Fanboy annoyances, from EasyList)
#
# SafariConverterLib is a GPL-3.0 offline build tool, not an app dependency.
# This script converts the source snapshots in vendor/blocklists. See that
# directory's README and manifest for provenance and refresh instructions.
# The generated data keeps the license of its source list.

set -euo pipefail

CONVERTER_REF="${CONVERTER_REF:-v4.3.0}"          # SafariConverterLib tag
SAFARI_VERSION="${SAFARI_VERSION:-14}"            # rule-syntax level for the converter, not the macOS target
CAP=150000                                        # WKContentRuleList per-list rule cap
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Building SafariConverterLib ConverterTool @ ${CONVERTER_REF} (build-only, GPLv3)"
git clone --quiet --depth 1 --branch "$CONVERTER_REF" \
  https://github.com/AdguardTeam/SafariConverterLib "$WORK/scl"
( cd "$WORK/scl" && swift build -c release --product ConverterTool )
TOOL="$WORK/scl/.build/release/ConverterTool"

# convert <source-path> <output-path> <label>
convert() {
  local source_path="$1" out="$2" label="$3"
  echo "==> Converting ${label} to WKContentRuleList JSON"
  "$TOOL" convert \
    --safari-version "$SAFARI_VERSION" \
    --advanced-blocking false \
    --input-path "$source_path" \
    --safari-rules-json-path "$WORK/rules.json"
  jq -e 'type == "array" and length > 0' "$WORK/rules.json" > /dev/null \
    || { echo "ERROR: ${label} produced no rules — refusing to write an empty list" >&2; exit 1; }
  local n; n=$(jq 'length' "$WORK/rules.json")
  echo "    ${n} rules converted"
  if [ "$n" -gt "$CAP" ]; then
    echo "NOTE: ${n} rules exceeds the ${CAP} per-list cap; the app splits into chunks at runtime."
  fi
  cp "$WORK/rules.json" "$out"
  echo "==> Wrote $out (${n} rules)"
}

convert \
  "$REPO_ROOT/vendor/blocklists/hagezi-light.txt" \
  "$REPO_ROOT/Blatta/Resources/hagezi-light.json" \
  "HaGezi Light snapshot"

convert \
  "$REPO_ROOT/vendor/blocklists/fanboy-annoyance.txt" \
  "$REPO_ROOT/Blatta/Resources/fanboy-annoyance.json" \
  "Fanboy Annoyance List (EasyList)"

echo "==> Done. Remember to commit the regenerated JSON."
