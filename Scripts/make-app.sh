#!/bin/bash
#
# Assembles TaskManager.app from the SwiftPM build.
#
# There is no Xcode project here on purpose, same reasoning as reclaim: the
# app is a plain package, and this script does the small amount of bundling
# that Xcode would otherwise do invisibly.
#
# The result is unsigned. macOS will refuse to open it on first launch until
# you right-click it and choose Open.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
BUILD_DIR="build"
APP="$BUILD_DIR/TaskManager.app"

echo "==> Building ($CONFIG)"
if [ "$CONFIG" = "release" ]; then
    swift build -c release --product TaskManager
    BINARY=".build/release/TaskManager"
else
    swift build --product TaskManager
    BINARY=".build/debug/TaskManager"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/TaskManager"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>TaskManager</string>
    <key>CFBundleIdentifier</key>          <string>app.taskmanager.TaskManager</string>
    <key>CFBundleName</key>                <string>Task Manager</string>
    <key>CFBundleDisplayName</key>         <string>Task Manager</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>0.1</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>Personal project.</string>
</dict>
</plist>
PLIST

touch "$APP"
echo "==> $APP"
