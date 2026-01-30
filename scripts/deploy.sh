#!/bin/bash
# Moltbot 部署脚本
# 用法: bash scripts/deploy.sh

set -e

SERVER="ubuntu@106.52.48.113"
REMOTE_DIR="~/moltbot"

echo "==> 1. 同步代码到服务器..."
rsync -avz --progress \
  --exclude node_modules \
  --exclude .git \
  --exclude dist \
  --exclude .next \
  --exclude .turbo \
  ./ ${SERVER}:${REMOTE_DIR}/

echo ""
echo "==> 2. 在服务器上构建和重启..."
ssh ${SERVER} << 'ENDSSH'
cd ~/moltbot
pnpm install
pnpm build
sudo systemctl restart moltbot
echo ""
echo "==> 部署完成！"
echo ""
echo "查看状态:"
echo "  sudo systemctl status moltbot"
echo "  pnpm moltbot channels status"
ENDSSH

echo ""
echo "✅ 部署完成！"
