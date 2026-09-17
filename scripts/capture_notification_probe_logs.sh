#!/bin/sh
set -eu

REPOSITORY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIRECTORY="$REPOSITORY_DIR/.project/logs"
OUTPUT_FILE="$LOG_DIRECTORY/notification-probe-latest.log"

mkdir -p "$LOG_DIRECTORY"

echo "Capturing privacy-limited notification provider diagnostics."
echo "Press Control-C to stop."
echo "The log file is $OUTPUT_FILE"

/usr/bin/log stream \
    --style compact \
    --level info \
    --predicate 'subsystem == "studio.anguria.paguro" AND category == "Notifications" AND (eventMessage CONTAINS "Provider probe:" OR eventMessage CONTAINS "Notification page click")' \
    2>&1 | tee "$OUTPUT_FILE"
