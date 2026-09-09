#!/bin/sh
# Measure what Paguro costs and say whether each number is acceptable.
#
# Usage:
#   scripts/audit_metrics.sh              measure the running app and the container
#   scripts/audit_metrics.sh --build      also build Release and measure the bundle
#   scripts/audit_metrics.sh --seconds 30 sample idle CPU for a different window
#
# Every measurement is judged against a budget below. The budgets encode what a
# native shell for web services should cost; the comment on each one says why.
# Change a budget when the product decides to spend more, not to silence a run.
#
# WebKit runs each service in its own process, so the shell process alone
# understates the cost. Quit other WebKit apps (Safari, other shells) before
# reading the memory section, or the helper total counts their pages too.
set -eu

# --- Budgets: WATCH threshold, FAIL threshold -------------------------------

# A user downloads this. Electron shells for the same job ship 100-200 MB, so
# staying under 40 MB is the whole point of being native.
BUDGET_DOWNLOAD_MB="40 100"
# Universal arm64+x86_64, unstripped by a plain `build`. Export strips it.
BUDGET_CODE_MB="30 60"
# Bundled blocklists and the asset catalog dominate. They compress well but
# still cost disk and launch-time mapping.
BUDGET_RESOURCES_MB="15 30"
# The SwiftUI/AppKit shell, excluding every WKWebView.
BUDGET_SHELL_MB="250 450"
# Per WebKit content process. A Safari tab runs 50-200 MB; a loaded service
# should sit in the same band, not above it.
BUDGET_HELPER_AVG_MB="150 250"
# CPU averaged over the whole life of the process. This is the number that
# predicts battery drain for an app that stays running all day. A short spot
# sample is not a substitute: it can land entirely inside one burst of real
# work and read 10% on an app that averages 1%.
BUDGET_LIFETIME_CPU_PCT="2.0 5.0"
# The largest single service store. Judged on the heaviest rather than the mean
# because most stores are near-empty and would hide one runaway service.
BUDGET_STORE_MAX_MB="150 400"
# Stores on disk that no ServiceInstance row points at. Judged on megabytes,
# not directory count: a phantom store is a near-empty skeleton, so hundreds of
# them cost little disk even though the count looks alarming.
BUDGET_ORPHAN_MB="100 300"
# Everything the app has written to disk.
BUDGET_CONTAINER_MB="600 1500"

REPOSITORY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SECONDS_TO_SAMPLE=15
BUILD_RELEASE=0
WATCH_COUNT=0
FAIL_COUNT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --build) BUILD_RELEASE=1 ;;
        --seconds) SECONDS_TO_SAMPLE=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

heading() {
    printf '\n== %s ==\n' "$1"
}

# judge LABEL VALUE UNIT "WATCH FAIL" [NOTE]
# Prints the value against its budget and records the verdict.
judge() {
    JUDGE_LABEL=$1
    JUDGE_VALUE=$2
    JUDGE_UNIT=$3
    JUDGE_WATCH=$(echo "$4" | cut -d' ' -f1)
    JUDGE_FAIL=$(echo "$4" | cut -d' ' -f2)
    JUDGE_NOTE=${5:-}
    JUDGE_VERDICT=$(awk -v v="$JUDGE_VALUE" -v w="$JUDGE_WATCH" -v f="$JUDGE_FAIL" \
        'BEGIN { if (v >= f) print "FAIL"; else if (v >= w) print "WATCH"; else print "ok" }')
    case "$JUDGE_VERDICT" in
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        WATCH) WATCH_COUNT=$((WATCH_COUNT + 1)) ;;
    esac
    printf '  %-22s %8s %-4s  %-5s  budget %s/%s%s\n' \
        "$JUDGE_LABEL" "$JUDGE_VALUE" "$JUDGE_UNIT" "$JUDGE_VERDICT" \
        "$JUDGE_WATCH" "$JUDGE_FAIL" \
        "${JUDGE_NOTE:+  $JUDGE_NOTE}"
}

# Size of a path in whole MB.
size_mb() {
    du -sk "$1" 2>/dev/null | awk '{printf "%.0f", $1/1024}'
}

# --- Source -----------------------------------------------------------------

heading "Source"
SWIFT_LINES=$(find "$REPOSITORY_DIR/Paguro" "$REPOSITORY_DIR/Core/Sources" -name '*.swift' -exec cat {} + | wc -l | tr -d ' ')
TEST_LINES=$(find "$REPOSITORY_DIR/PaguroTests" "$REPOSITORY_DIR/Core/Tests" -name '*.swift' -exec cat {} + | wc -l | tr -d ' ')
printf '  %-22s %8s lines\n' "shipping Swift" "$SWIFT_LINES"
printf '  %-22s %8s lines (%s%% of shipping)\n' "tests" "$TEST_LINES" \
    "$(awk -v t="$TEST_LINES" -v s="$SWIFT_LINES" 'BEGIN {printf "%.0f", 100*t/s}')"
printf '  largest files\n'
find "$REPOSITORY_DIR/Paguro" "$REPOSITORY_DIR/Core/Sources" -name '*.swift' -exec wc -l {} + \
    | sort -rn | sed -n '2,4p' | sed "s|$REPOSITORY_DIR/|    |"

# --- Bundle -----------------------------------------------------------------

if [ "$BUILD_RELEASE" -eq 1 ]; then
    heading "Release build"
    DERIVED_DIR="$REPOSITORY_DIR/.build/audit"
    BUILD_START=$(date +%s)
    xcodebuild -project "$REPOSITORY_DIR/Paguro.xcodeproj" \
        -scheme Paguro -configuration Release \
        -derivedDataPath "$DERIVED_DIR" \
        CODE_SIGNING_ALLOWED=NO build >/dev/null
    printf '  %-22s %8s s\n' "incremental build" "$(( $(date +%s) - BUILD_START ))"
    APP_PATH="$DERIVED_DIR/Build/Products/Release/Paguro.app"
else
    # Prefer Release, then the most recently built bundle that has a real
    # executable. Preview-only bundles carry just a __preview.dylib.
    APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 -name Paguro.app -print 2>/dev/null \
        | while read -r CANDIDATE; do
              [ -f "$CANDIDATE/Contents/MacOS/Paguro" ] || continue
              RANK=1
              [ "${CANDIDATE#*/Release/}" = "$CANDIDATE" ] || RANK=0
              printf '%s %s %s\n' "$RANK" "$(stat -f %m "$CANDIDATE/Contents/MacOS/Paguro")" "$CANDIDATE"
          done | sort -k1,1n -k2,2rn | head -1 | cut -d' ' -f3-)
fi

if [ -n "${APP_PATH:-}" ] && [ -d "$APP_PATH" ]; then
    BUILD_KIND=$(basename "$(dirname "$APP_PATH")")
    heading "Bundle ($BUILD_KIND)"
    # Debug builds split the code into Paguro.debug.dylib, so measure the
    # largest Mach-O in the bundle rather than assuming the launcher holds it.
    MAIN_BINARY=$(find "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Frameworks" -type f -perm -u+x 2>/dev/null \
        | while read -r BINARY; do printf '%s %s\n' "$(stat -f %z "$BINARY")" "$BINARY"; done \
        | sort -rn | head -1 | cut -d' ' -f2-)
    ditto -c -k --keepParent "$APP_PATH" /tmp/paguro-audit.zip 2>/dev/null
    DOWNLOAD_MB=$(size_mb /tmp/paguro-audit.zip)
    rm -f /tmp/paguro-audit.zip
    ARCHS=$(lipo -archs "$MAIN_BINARY" 2>/dev/null || echo "?")

    judge "download (zipped)" "$DOWNLOAD_MB" MB "$BUDGET_DOWNLOAD_MB"
    judge "code" "$(size_mb "$MAIN_BINARY")" MB "$BUDGET_CODE_MB" "$ARCHS, unstripped"
    judge "resources" "$(size_mb "$APP_PATH/Contents/Resources")" MB "$BUDGET_RESOURCES_MB"
    printf '  heaviest resources\n'
    du -h "$APP_PATH/Contents/Resources"/* 2>/dev/null | sort -rh | head -3 \
        | awk -F'\t' '{n=$2; sub(/.*\//,"",n); printf "    %-24s %s\n", n, $1}'
else
    heading "Bundle"
    echo "  no built Paguro.app found; pass --build"
fi

# --- Runtime ----------------------------------------------------------------

APP_PID=$(pgrep -f 'Paguro.app/Contents/MacOS/Paguro' | head -1 || true)

heading "Memory"
if [ -z "$APP_PID" ]; then
    echo "  Paguro is not running; launch it and rerun for the runtime sections"
else
    SHELL_MB=$(/usr/bin/footprint -p "$APP_PID" 2>/dev/null \
        | awk '/phys_footprint:/ {print $2; exit}')
    [ -n "$SHELL_MB" ] || SHELL_MB=$(ps -p "$APP_PID" -o rss= | awk '{printf "%.0f", $1/1024}')
    judge "shell process" "$SHELL_MB" MB "$BUDGET_SHELL_MB" "pid $APP_PID, no WKWebViews"

    WEBKIT_PIDS=$(pgrep -f 'WebKit.framework/Versions/A/XPCServices' | tr '\n' ',' | sed 's/,$//' || true)
    if [ -n "$WEBKIT_PIDS" ]; then
        set -- $(ps -o rss= -p "$WEBKIT_PIDS" \
            | awk '{rss+=$1; n++; if ($1>max) max=$1}
                   END {printf "%d %.0f %.0f %.0f", n, rss/1024, rss/1024/n, max/1024}')
        judge "WebKit helper (avg)" "$3" MB "$BUDGET_HELPER_AVG_MB" "$1 processes, heaviest $4 MB"
        printf '  %-22s %8s MB   machine-wide, includes other WebKit apps\n' "WebKit helpers total" "$2"
    fi
fi

heading "CPU"
if [ -n "$APP_PID" ]; then
    # ps -o time is cumulative CPU; ps -o etime is wall clock since launch.
    to_seconds() {
        echo "$1" | tr '-' ':' \
            | awk -F: '{s=0; for (i=1; i<=NF; i++) s = s*60 + $i; print s}'
    }
    CPU_TOTAL=$(to_seconds "$(ps -p "$APP_PID" -o time= | tr -d ' ')")
    WALL_TOTAL=$(to_seconds "$(ps -p "$APP_PID" -o etime= | tr -d ' ')")
    LIFETIME_PCT=$(awk -v c="$CPU_TOTAL" -v w="$WALL_TOTAL" \
        'BEGIN {printf "%.2f", w ? 100*c/w : 0}')
    judge "lifetime CPU" "$LIFETIME_PCT" % "$BUDGET_LIFETIME_CPU_PCT" \
        "$(awk -v c="$CPU_TOTAL" -v w="$WALL_TOTAL" \
            'BEGIN {printf "%.0fs CPU over %.0f min uptime", c, w/60}')"

    # Spot samples, reported as a range. Three short windows make a burst
    # visible as spread instead of dressing it up as a steady rate.
    printf '  %-22s ' "spot samples"
    SPOT_WINDOW=$((SECONDS_TO_SAMPLE / 3))
    [ "$SPOT_WINDOW" -ge 3 ] || SPOT_WINDOW=3
    SPOT_RESULTS=""
    for _ in 1 2 3; do
        SPOT_BEFORE=$(to_seconds "$(ps -p "$APP_PID" -o time= | tr -d ' ')")
        sleep "$SPOT_WINDOW"
        SPOT_AFTER=$(to_seconds "$(ps -p "$APP_PID" -o time= | tr -d ' ')")
        SPOT_RESULTS="$SPOT_RESULTS $(awk -v a="$SPOT_BEFORE" -v b="$SPOT_AFTER" -v t="$SPOT_WINDOW" \
            'BEGIN {printf "%.1f", 100*(b-a)/t}')"
    done
    printf '%s  %%  (%ss windows; wide spread means bursty, not idle-hot)\n' \
        "$SPOT_RESULTS" "$SPOT_WINDOW"
else
    echo "  skipped, app not running"
fi

# --- Stored data ------------------------------------------------------------

heading "Stored data"
for BUNDLE_ID in studio.anguria.paguro studio.anguria.paguro.debug; do
    CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"
    [ -d "$CONTAINER" ] || continue
    printf '  %s\n' "$BUNDLE_ID"
    judge "container" "$(size_mb "$CONTAINER")" MB "$BUDGET_CONTAINER_MB"

    STORE_DIR="$CONTAINER/Data/Library/WebKit/WebsiteDataStore"
    [ -d "$STORE_DIR" ] || continue

    # An orphan is a store on disk with no ServiceInstance row pointing at it.
    # Comparing against the catalog instead would be wrong: the catalog lists
    # service types on offer, not the accounts the user actually configured.
    SWIFT_DATA_STORE=$(find "$CONTAINER/Data/Library/Application Support" \
        -maxdepth 2 -name 'default.store' -print 2>/dev/null | head -1)
    find "$STORE_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; \
        | tr 'A-Z' 'a-z' | sort > /tmp/paguro-ondisk.txt
    if [ -n "$SWIFT_DATA_STORE" ] && command -v sqlite3 >/dev/null; then
        sqlite3 "$SWIFT_DATA_STORE" \
            'select lower(hex(ZDATASTOREIDENTIFIER)) from ZSERVICEINSTANCE;' 2>/dev/null \
            | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/' \
            | sort > /tmp/paguro-live.txt
    else
        : > /tmp/paguro-live.txt
    fi

    sum_mb() {
        while read -r STORE_UUID; do du -sk "$STORE_DIR/$STORE_UUID" 2>/dev/null | cut -f1; done \
            | awk '{s+=$1} END {printf "%.0f", s/1024}'
    }
    LIVE_COUNT=$(wc -l < /tmp/paguro-live.txt | tr -d ' ')
    ORPHAN_COUNT=$(comm -13 /tmp/paguro-live.txt /tmp/paguro-ondisk.txt | wc -l | tr -d ' ')
    ORPHAN_MB=$(comm -13 /tmp/paguro-live.txt /tmp/paguro-ondisk.txt | sum_mb)
    LIVE_MB=$(comm -12 /tmp/paguro-live.txt /tmp/paguro-ondisk.txt | sum_mb)

    if [ "$LIVE_COUNT" -eq 0 ]; then
        printf '    %-20s %8s      could not read ServiceInstance rows\n' "orphans" "?"
    else
        printf '    %-20s %8s MB   %s services\n' "live services" "${LIVE_MB:-0}" "$LIVE_COUNT"
        judge "orphaned stores" "${ORPHAN_MB:-0}" MB "$BUDGET_ORPHAN_MB" \
            "$ORPHAN_COUNT dirs with no service row"
        STORE_MAX=$(comm -12 /tmp/paguro-live.txt /tmp/paguro-ondisk.txt \
            | while read -r STORE_UUID; do du -sm "$STORE_DIR/$STORE_UUID" 2>/dev/null | cut -f1; done \
            | sort -rn | head -1)
        judge "heaviest live store" "${STORE_MAX:-0}" MB "$BUDGET_STORE_MAX_MB"
    fi
    rm -f /tmp/paguro-ondisk.txt /tmp/paguro-live.txt

    for SUBDIR in "Data/Library/WebKit/ContentRuleLists" "Data/Library/Caches"; do
        [ -d "$CONTAINER/$SUBDIR" ] || continue
        printf '    %-20s %8s MB\n' "$(basename "$SUBDIR")" "$(size_mb "$CONTAINER/$SUBDIR")"
    done
done

# --- Verdict ----------------------------------------------------------------

heading "Verdict"
if [ "$FAIL_COUNT" -gt 0 ]; then
    printf '  %s over budget, %s worth watching\n' "$FAIL_COUNT" "$WATCH_COUNT"
elif [ "$WATCH_COUNT" -gt 0 ]; then
    printf '  nothing over budget, %s worth watching\n' "$WATCH_COUNT"
else
    printf '  everything within budget\n'
fi

printf '\n  deeper passes\n'
printf '    leaks %s\n' "${APP_PID:-<pid>}"
printf '    xcrun xctrace record --template "Time Profiler" --attach %s --output /tmp/paguro.trace\n' "${APP_PID:-<pid>}"
printf '    sudo powermetrics --samplers tasks --show-process-coalition -n 1 | grep -A12 Paguro\n'

[ "$FAIL_COUNT" -eq 0 ]
