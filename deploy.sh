#!/bin/bash
# 編譯後部署到各台 Mac：./deploy.sh [host ...]；不帶參數時讀 deploy-hosts.txt（一行一個 SSH host，不進版控）
set -uo pipefail
cd "$(dirname "$0")"
./build.sh --no-install >/dev/null || exit 1
HOSTS=${*:-$(grep -v "^#" deploy-hosts.txt 2>/dev/null)}
[ -n "$HOSTS" ] || { echo "用法：./deploy.sh host1 host2 …，或建立 deploy-hosts.txt"; exit 1; }
for h in $HOSTS; do
  echo "== $h"
  ssh -o ConnectTimeout=5 "$h" 'mkdir -p ~/.mdview-deploy' &&
  rsync -a --delete build/MDView.app install.sh "$h:.mdview-deploy/" &&
  ssh "$h" 'bash ~/.mdview-deploy/install.sh ~/.mdview-deploy/MDView.app && rm -rf ~/.mdview-deploy' || echo "!! $h 失敗"
done
