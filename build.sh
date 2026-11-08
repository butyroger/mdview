#!/bin/bash
# 編譯 MDView.app（arm64＋x86_64 通用版，macOS 12+）；不帶參數時順便裝到本機，`./build.sh --no-install` 只編譯
set -euo pipefail
cd "$(dirname "$0")"
APP=build/MDView.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
universal() { # $1=輸出 其餘=swiftc 參數
  local out=$1; shift
  for a in arm64 x86_64; do swiftc -O -target $a-apple-macos12.0 -o "$out.$a" "$@"; done
  lipo -create -output "$out" "$out.arm64" "$out.x86_64"; rm -f "$out.arm64" "$out.x86_64"
}
universal "$APP/Contents/MacOS/MDView" main.swift -framework AppKit -framework WebKit
cp Info.plist "$APP/Contents/"
cp Resources/* "$APP/Contents/Resources/"
# Quick Look 預覽外掛
EXT="$APP/Contents/PlugIns/MDViewQuickLook.appex"
mkdir -p "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
universal "$EXT/Contents/MacOS/MDViewQuickLook" -module-name MDViewQuickLook QuickLook/PreviewViewController.swift \
  -framework Cocoa -framework Quartz -framework WebKit -Xlinker -e -Xlinker _NSExtensionMain
cp QuickLook/Info.plist "$EXT/Contents/"
cp Resources/* "$EXT/Contents/Resources/"
codesign --force -s - --entitlements QuickLook/QuickLook.entitlements "$EXT"
codesign --force -s - "$APP"
echo "built $APP"
[ "${1:-}" = "--no-install" ] || ./install.sh "$APP"
