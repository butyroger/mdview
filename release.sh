#!/bin/bash
# 打包 DMG 並發布到 GitHub Releases：./release.sh 1.1
set -euo pipefail
cd "$(dirname "$0")"
VER=${1:?版本號，例如 1.1}
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" QuickLook/Info.plist
./build.sh --no-install
STAGE=$(mktemp -d); cp -R build/MDView.app "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG=build/MDView-$VER.dmg; rm -f "$DMG"
hdiutil create -volname "MDView $VER" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
git add Info.plist QuickLook/Info.plist && git commit -qm "v$VER" || true
git push -q
gh release create "v$VER" "$DMG" --title "MDView $VER" --notes-file release-notes.md
