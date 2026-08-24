#!/bin/sh
set -eu

REPOSITORY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 -m unittest discover \
    -s "$REPOSITORY_DIR/fixtures/compatibility" \
    -p "test_*.py"
