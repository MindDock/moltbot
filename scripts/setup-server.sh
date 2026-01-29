#!/bin/bash
#
# Moltbot 服务器端安装脚本
# 直接在服务器上运行此脚本完成部署
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/moltbot/moltbot/main/scripts/setup-server.sh | bash
#   或下载后运行: bash setup-server.sh
#

set -e

# ============== 颜色定义 ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}==>${NC} ${CYAN}$1${NC}"; }

# ============== 配置变量 ==============
MOLTBOT_DIR="${MOLTBOT_DIR:-$HOME/moltbot}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

# ============== 检查 root ==============
if [[ $EUID -eq 0 ]]; then
    log_error "请勿使用 root 用户运行此脚本"
    log_info "请使用普通用户运行，需要 sudo 权限时会自动提示"
    exit 1
fi

# ============== 开始安装 ==============
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Moltbot 国内服务器部署脚本           ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ============== 第一步：安装系统依赖 ==============
log_step "第一步：安装系统依赖"

# Node.js 22
log_info "检查 Node.js..."
if command -v node &> /dev/null && [[ $(node --version) =~ ^v22 ]]; then
    log_success "Node.js 已安装: $(node --version)"
else
    log_info "安装 Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    log_success "Node.js 已安装: $(node --version)"
fi

# pnpm
log_info "检查 pnpm..."
if command -v pnpm &> /dev/null; then
    log_success "pnpm 已安装: $(pnpm --version)"
else
    log_info "安装 pnpm..."
    sudo npm install -g pnpm
    log_success "pnpm 已安装: $(pnpm --version)"
fi

# nginx
log_info "检查 nginx..."
if command -v nginx &> /dev/null; then
    log_success "nginx 已安装"
else
    log_info "安装 nginx..."
    sudo apt-get install -y nginx
    log_success "nginx 已安装"
fi

# git
log_info "检查 git..."
if command -v git &> /dev/null; then
    log_success "git 已安装"
else
    log_info "安装 git..."
    sudo apt-get install -y git
    log_success "git 已安装"
fi

# ============== 第二步：配置 nginx ==============
log_step "第二步：配置 nginx"

sudo tee /etc/nginx/sites-available/moltbot > /dev/null << EOF
server {
    listen 80;
    server_name _;

    location /api/webhook/feishu {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT}/api/webhook/feishu;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /api/webhook/wecom {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT}/api/webhook/wecom;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        return 200 'Moltbot Server';
        add_header Content-Type text/plain;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
log_success "nginx 配置完成"

# ============== 第三步：获取代码 ==============
log_step "第三步：获取 Moltbot 代码"

if [[ -d "$MOLTBOT_DIR/.git" ]]; then
    log_info "更新现有代码..."
    cd "$MOLTBOT_DIR"
    git pull
    log_success "代码更新完成"
elif [[ -d "$MOLTBOT_DIR" ]]; then
    log_warn "目录已存在但非 git 仓库，跳过克隆"
    log_info "如需重新克隆，请先删除: rm -rf $MOLTBOT_DIR"
else
    log_info "克隆代码..."
    git clone https://github.com/moltbot/moltbot.git "$MOLTBOT_DIR"
    log_success "代码克隆完成"
fi

cd "$MOLTBOT_DIR"

# ============== 第四步：安装依赖并构建 ==============
log_step "第四步：安装依赖并构建"

log_info "安装依赖 (可能需要几分钟)..."
pnpm install

log_info "构建项目..."
pnpm build

log_success "构建完成"

# ============== 第五步：交互式配置 ==============
log_step "第五步：配置 Moltbot"

# Gateway 配置
log_info "配置 Gateway..."
pnpm moltbot config set gateway.mode local

read -p "请输入 Gateway Token (留空自动生成): " GATEWAY_TOKEN
if [[ -z "$GATEWAY_TOKEN" ]]; then
    GATEWAY_TOKEN="moltbot-$(openssl rand -hex 8)"
fi
pnpm moltbot config set gateway.auth.token "$GATEWAY_TOKEN"
log_success "Gateway Token: $GATEWAY_TOKEN"

# DeepSeek 配置
echo ""
read -p "请输入 DeepSeek API Key (留空跳过): " DEEPSEEK_API_KEY
if [[ -n "$DEEPSEEK_API_KEY" ]]; then
    pnpm moltbot config set providers.deepseek.apiKey "$DEEPSEEK_API_KEY"
    pnpm moltbot config set models.default 'deepseek/deepseek-chat'
    log_success "DeepSeek 配置完成"
fi

# 飞书配置
echo ""
read -p "是否配置飞书? (y/n): " SETUP_FEISHU
if [[ "$SETUP_FEISHU" =~ ^[Yy] ]]; then
    pnpm moltbot config set channels.feishu.enabled true

    read -p "飞书 App ID: " FEISHU_APP_ID
    pnpm moltbot config set channels.feishu.appId "$FEISHU_APP_ID"

    read -p "飞书 App Secret: " FEISHU_APP_SECRET
    pnpm moltbot config set channels.feishu.appSecret "$FEISHU_APP_SECRET"

    read -p "飞书 Verification Token: " FEISHU_VERIFICATION_TOKEN
    pnpm moltbot config set channels.feishu.verificationToken "$FEISHU_VERIFICATION_TOKEN"

    read -p "飞书 Encrypt Key (可选，留空跳过): " FEISHU_ENCRYPT_KEY
    if [[ -n "$FEISHU_ENCRYPT_KEY" ]]; then
        pnpm moltbot config set channels.feishu.encryptKey "$FEISHU_ENCRYPT_KEY"
    fi

    pnpm moltbot config set channels.feishu.webhookUrl "http://${SERVER_IP}/api/webhook/feishu"

    read -p "允许的用户 open_id (逗号分隔，留空允许所有): " FEISHU_ALLOW_FROM
    if [[ -n "$FEISHU_ALLOW_FROM" ]]; then
        ALLOW_FROM_JSON=$(echo "$FEISHU_ALLOW_FROM" | sed 's/ //g' | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
        pnpm moltbot config set channels.feishu.allowFrom "$ALLOW_FROM_JSON"
        pnpm moltbot config set channels.feishu.dmPolicy 'allowlist'
    else
        pnpm moltbot config set channels.feishu.dmPolicy 'open'
    fi

    log_success "飞书配置完成"
fi

# ============== 第六步：创建 systemd 服务 ==============
log_step "第六步：配置开机自启"

read -p "是否创建 systemd 服务 (开机自启)? (y/n): " SETUP_SYSTEMD
if [[ "$SETUP_SYSTEMD" =~ ^[Yy] ]]; then
    sudo tee /etc/systemd/system/moltbot.service > /dev/null << EOF
[Unit]
Description=Moltbot Gateway
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MOLTBOT_DIR
ExecStart=$(which pnpm) moltbot gateway run --bind 0.0.0.0 --port ${GATEWAY_PORT} --force
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable moltbot
    sudo systemctl start moltbot
    log_success "systemd 服务已创建并启动"
else
    # 后台启动
    log_info "后台启动 Gateway..."
    pkill -9 -f 'moltbot.*gateway' 2>/dev/null || true
    sleep 1
    nohup pnpm moltbot gateway run --bind 0.0.0.0 --port ${GATEWAY_PORT} --force > /tmp/moltbot-gateway.log 2>&1 &
    sleep 3
    if pgrep -f 'moltbot.*gateway' > /dev/null; then
        log_success "Gateway 启动成功"
    else
        log_error "Gateway 启动失败，请查看日志: tail -50 /tmp/moltbot-gateway.log"
    fi
fi

# ============== 完成 ==============
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    部署完成!                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "服务器地址:     http://${SERVER_IP}"
echo "飞书 Webhook:   http://${SERVER_IP}/api/webhook/feishu"
echo "Gateway Token:  ${GATEWAY_TOKEN}"
echo "安装目录:       ${MOLTBOT_DIR}"
echo ""
echo "常用命令:"
echo "  查看日志:     tail -f /tmp/moltbot-gateway.log"
echo "  查看状态:     cd $MOLTBOT_DIR && pnpm moltbot channels status"
echo "  重启服务:     sudo systemctl restart moltbot"
echo "  修改配置:     cd $MOLTBOT_DIR && pnpm moltbot config set <key> <value>"
echo ""
echo "飞书配置提示:"
echo "  1. 在飞书开放平台设置事件订阅 URL: http://${SERVER_IP}/api/webhook/feishu"
echo "  2. 添加事件: im.message.receive_v1"
echo "  3. 开通权限: im:message:send_as_bot"
echo "  4. 发布应用版本"
echo ""
