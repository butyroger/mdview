#!/bin/bash
# 編譯後部署到各台 Mac：./deploy.sh [host ...]（預設 neo imac sindy2 rosida young）
set -uo pipefail
cd "$(dirname "$0")"
./build.sh --no-install >/dev/null || exit 1
HOSTS=${*:-neo imac sindy2 rosida young}
for h in $HOSTS; do
  echo "== $h"
  ssh -o ConnectTimeout=5 "$h" 'mkdir -p ~/.mdview-deploy' &&
  rsync -a --delete build/MDView.app install.sh "$h:.mdview-deploy/" &&
  ssh "$h" 'bash ~/.mdview-deploy/install.sh ~/.mdview-deploy/MDView.app && rm -rf ~/.mdview-deploy' || echo "!! $h 失敗"
done
