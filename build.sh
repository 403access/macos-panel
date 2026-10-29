#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="MacosPanel"
APP_DIR="build/${APP_NAME}.app"

swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>dev.olivermolnar.macos-panel</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if codesign --force --sign - "$APP_DIR" 2>/dev/null; then
    echo "Signed ad-hoc"
else
    echo "warning: ad-hoc signing failed; launch-at-login may not work" >&2
fi

echo "Built ${APP_DIR}"

if [[ "${1:-}" == "run" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    open "$APP_DIR"
    echo "Launched ${APP_NAME}"
fi
