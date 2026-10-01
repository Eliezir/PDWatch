#!/usr/bin/env bash
# Builds PDWatch.app (a menu bar app with no Dock icon) into ./build
#
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications and relaunch
#
# VERSION=1.2.0 ./build.sh sets the version shown in Finder (default 0.1.0).
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=false
case "${1:-}" in
    --install) INSTALL=true ;;
    "") ;;
    *) echo "Usage: $0 [--install]" >&2; exit 64 ;;
esac

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/PDWatch"
APP="build/PDWatch.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PDWatch"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PDWatch</string>
    <key>CFBundleDisplayName</key><string>PDWatch</string>
    <key>CFBundleIdentifier</key><string>local.pdwatch</string>
    <key>CFBundleExecutable</key><string>PDWatch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER)."

if $INSTALL; then
    pkill -x PDWatch && sleep 1 || true
    rm -rf /Applications/PDWatch.app
    ditto "$APP" /Applications/PDWatch.app
    open /Applications/PDWatch.app
    echo "Installed to /Applications/PDWatch.app and launched it."
fi
