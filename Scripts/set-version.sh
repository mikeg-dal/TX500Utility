#!/bin/bash
# Sets the project version in the two places that must agree: the VERSION file and the Swift
# fallback the app uses when run without a bundle. They are edited by hand and used by different
# things, so setting them separately is how they drift — build-app.sh refuses to build when they do.
#
# Usage: Scripts/set-version.sh 0.9.1
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-}"
SWIFT_FILE="Sources/TX500Utility/App/TX500UtilityApp.swift"

if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Usage: Scripts/set-version.sh <major.minor.patch>   e.g. 0.9.1" >&2
    exit 1
fi

printf '%s\n' "$VERSION" > VERSION
# Rewrites the constant in place, leaving the surrounding doc comment alone.
sed -i '' "s/fallbackVersion = \"[^\"]*\"/fallbackVersion = \"$VERSION\"/" "$SWIFT_FILE"

echo "VERSION          $(tr -d '[:space:]' < VERSION)"
echo "fallbackVersion  $(sed -n 's/.*fallbackVersion = "\([^"]*\)".*/\1/p' "$SWIFT_FILE")"
echo
echo "Next: commit the bump, push, then tag v$VERSION"
