#!/bin/sh
set -eu

REPOSITORY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIRECTORY="$REPOSITORY_DIR/.project/logs"
OUTPUT_FILE="$LOG_DIRECTORY/service-test-latest.log"

mkdir -p "$LOG_DIRECTORY"

echo "Capturing Paguro service test logs."
echo "Press Control-C to stop."
echo "The log file is $OUTPUT_FILE"

/usr/bin/log stream \
    --style compact \
    --level info \
    --predicate 'subsystem == "com.tommasolaterza.Paguro" AND category == "WebView"' \
    2>&1 | tee "$OUTPUT_FILE"
