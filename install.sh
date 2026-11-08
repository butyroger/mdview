#!/bin/bash
# 安裝 MDView 到目前使用者：~/Applications、Quick Look 外掛、連結中繼 LaunchAgent、.md 預設程式
# 用法：install.sh <MDView.app 路徑>（本機 build.sh 與遠端 deploy.sh 共用）
set -euo pipefail
SRC=${1:?MDView.app path}
DEST="$HOME/Applications/MDView.app"
mkdir -p "$HOME/Applications"
pkill -f "MDView.app/Contents/MacOS/MDView" 2>/dev/null || true
pkill -x MDViewQuickLook 2>/dev/null || true
rm -rf "$DEST"; cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/MDViewQuickLook.appex" || true
sleep 2; pluginkit -e use -i com.butyshop.mdview.quicklook || true
# 舊的 MD Viewer／QLMarkdown（預覽連結點不了）停用並移到垃圾桶
pluginkit -m -p com.apple.quicklook.preview 2>/dev/null | grep -q org.sbarex.QLMarkdown && pluginkit -e ignore -i org.sbarex.QLMarkdown.QLExtension || true
for old in "/Applications/MD Viewer.app" "/Applications/QLMarkdown.app" "$HOME/Applications/MD Viewer.app" "$HOME/Applications/QLMarkdown.app"; do
  [ -e "$old" ] || continue
  pkill -f "$old/Contents/MacOS" 2>/dev/null || true
  name=$(basename "$old"); dst="$HOME/.Trash/$name"; [ -e "$dst" ] && dst="$HOME/.Trash/${name%.app} $(date +%H%M%S).app"
  mv "$old" "$dst" 2>/dev/null || sudo -n mv "$old" "$dst" 2>/dev/null || echo "!! 無法移除 $old（需要管理員權限）"
  [ -e "$old" ] || echo "已移到垃圾桶：$name"
done
# 連結中繼 LaunchAgent（Quick Look 預覽點連結用，XPC mach 服務，按需啟動）
PL="$HOME/Library/LaunchAgents/com.butyshop.mdview.linkhelper.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.butyshop.mdview.linkhelper</string>
<key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/MDView</string><string>--link-helper</string></array>
<key>MachServices</key><dict><key>com.butyshop.mdview.linkhelper</key><true/></dict>
<key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/com.butyshop.mdview.linkhelper 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PL"
"$DEST/Contents/MacOS/MDView" --set-default
pluginkit -e use -i com.butyshop.mdview.quicklook || true
qlmanage -r >/dev/null 2>&1 || true
echo "installed $DEST on $(scutil --get ComputerName)"
