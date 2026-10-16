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
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

if [[ "${1:-}" != "--no-launch" ]]; then
    open "$app"
fi
echo "Installed $app"
