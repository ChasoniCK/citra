#!/bin/bash
# Builds a universal, ad-hoc signed Release of Citra and packs it as dist/Citra-<version>.zip for GitHub Releases.
# Ad-hoc signing needs no Apple Developer account; users confirm the first launch once (README › Installation).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

# Build outside the project folder: iCloud Drive's file-provider attributes make codesign fail.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
log="$work/build.log"
# Ad-hoc forced on the command line, so a local Signing.local.xcconfig never leaks a personal certificate.
if ! xcodebuild -project Citra.xcodeproj -scheme Citra -configuration Release -destination 'generic/platform=macOS' \
        -derivedDataPath "$work/derived" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build >"$log" 2>&1; then
    grep -E "error:" "$log" || tail -30 "$log"
    exit 1
fi
app="$work/derived/Build/Products/Release/Citra.app"

codesign --verify --strict --deep "$app"
if codesign -dv "$app" 2>&1 | grep -q "TeamIdentifier=[A-Z0-9]"; then
    echo "Refusing to package: the app is signed with a personal team, not ad-hoc." >&2
    exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p dist
zip="dist/Citra-$version.zip"
rm -f "$zip"
# ditto keeps the bundle and its signature intact; a plain `zip` can break both.
ditto -c -k --keepParent "$app" "$zip"

echo "Built $zip ($(lipo -archs "$app/Contents/MacOS/Citra"))"
shasum -a 256 "$zip"
