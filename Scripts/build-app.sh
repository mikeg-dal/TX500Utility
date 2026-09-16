#!/bin/bash
# Builds "TX500 Utility.app" — a normal double-clickable macOS app with the Lab599 icon.
# Usage: Scripts/build-app.sh [output-directory]   (default: ./build)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-build}"
APP_NAME="TX500 Utility"
APP="$OUT_DIR/$APP_NAME.app"
BUNDLE_ID="com.kf5o.tx500utility"
EXECUTABLE="TX500Utility"

# The VERSION file is the default; CI overrides it with TX500_VERSION so the app inside a build
# reports the same version the build is named after. Without this an untagged build was named
# "main-<sha>" while the app inside it claimed to be the VERSION file's release number.
if [ -n "${TX500_VERSION:-}" ]; then
    VERSION="$TX500_VERSION"
    echo "Version: $VERSION (from TX500_VERSION)"
else
    VERSION="$(tr -d '[:space:]' < "VERSION")"
    if [ -z "$VERSION" ]; then
        echo "VERSION file is empty" >&2
        exit 1
    fi
    # Only checked for local builds. The app falls back to a constant when run without a bundle
    # (swift run), and these two are edited by hand, so they are exactly the pair that drifts.
    # Scripts/set-version.sh sets both at once.
    FALLBACK="$(sed -n 's/.*fallbackVersion = "\([^"]*\)".*/\1/p' "Sources/TX500Utility/App/TX500UtilityApp.swift")"
    if [ "$FALLBACK" != "$VERSION" ]; then
        echo "Version mismatch: VERSION says '$VERSION', AppStrings.fallbackVersion says '$FALLBACK'." >&2
        echo "Run Scripts/set-version.sh $VERSION to set both." >&2
        exit 1
    fi
fi

echo "Building release binary…"
swift build -c release --arch arm64 --product "$EXECUTABLE"
BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)"

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (splash artwork) go in Contents/Resources only. Bundle.module searches
# the main bundle's resource path, so that is where it finds them. A copy next to the executable
# also worked, but a .bundle inside Contents/MacOS is not a valid nested-code location and
# codesign refuses the whole app for it: "bundle format unrecognized, invalid, or unsuitable".
for bundle in "$BIN_PATH"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>An independent utility by Mike (KF5O). Not affiliated with or endorsed by Lab599. Lab599, TX-500 and the 599lab logo are their trademarks.</string>
</dict>
PLIST
echo "</plist>" >> "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS runs it locally without a developer certificate.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing skipped"
touch "$APP"

echo "Built $APP"
