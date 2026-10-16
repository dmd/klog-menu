#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scratch="$HOME/Library/Caches/klog-menu-build"
app="$HOME/Applications/KlogMenu.app"

swift build -c release --scratch-path "$scratch"
binary="$(swift build -c release --scratch-path "$scratch" --show-bin-path)/KlogMenu"

pkill -x KlogMenu 2>/dev/null || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/KlogMenu"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>KlogMenu</string>
    <key>CFBundleIdentifier</key><string>org.3e.klog-menu</string>
    <key>CFBundleName</key><string>KlogMenu</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"

if [[ "${1:-}" != "--no-launch" ]]; then
    open "$app"
fi
echo "Installed $app"
