#!/usr/bin/env bash

set -euo pipefail

if ! command -v vale >/dev/null 2>&1; then
  echo "Vale is not installed. Install it with: brew install vale" >&2
  exit 127
fi

cd "$(dirname "$0")/.."

vale \
  README.md \
  CHANGELOG.md \
  CONTRIBUTING.md \
  AGENTS.md \
  THIRD_PARTY_NOTICES.md \
  docs
