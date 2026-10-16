#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
version="${1:?usage: ./release.sh VERSION (e.g. 0.1.0)}"
scratch="$HOME/Library/Caches/klog-menu-build"
dist="dist"
app="$dist/KlogMenu.app"
build_args=(-c release --arch arm64 --arch x86_64 --scratch-path "$scratch")

swift build "${build_args[@]}"
binary="$(swift build "${build_args[@]}" --show-bin-path)/KlogMenu"

rm -rf "$dist"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/KlogMenu"
cp Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
ditto -c -k --keepParent "$app" "$dist/KlogMenu-$version.zip"
echo "Built $dist/KlogMenu-$version.zip"
