#!/bin/bash
#
# Moltbot 服务器端自动安装脚本 (非交互式)
# 所有配置通过环境变量传入
#
# 用法:
#   DEEPSEEK_API_KEY=xxx FEISHU_APP_ID=xxx ... bash setup-server-auto.sh
#

set -e

# ============== 颜色定义 ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ============== 配置变量 ==============
MOLTBOT_DIR="${MOLTBOT_DIR:-$HOME/moltbot}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-moltbot-$(openssl rand -hex 8)}"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

# DeepSeek
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek/deepseek-chat}"

# 飞书
FEISHU_APP_ID="${FEISHU_APP_ID:-}"
FEISHU_APP_SECRET="${FEISHU_APP_SECRET:-}"
FEISHU_VERIFICATION_TOKEN="${FEISHU_VERIFICATION_TOKEN:-}"
FEISHU_ENCRYPT_KEY="${FEISHU_ENCRYPT_KEY:-}"
FEISHU_ALLOW_FROM="${FEISHU_ALLOW_FROM:-}"
FEISHU_DM_POLICY="${FEISHU_DM_POLICY:-allowlist}"

# 选项
SKIP_DEPS="${SKIP_DEPS:-false}"
SKIP_BUILD="${SKIP_BUILD:-false}"
USE_SYSTEMD="${USE_SYSTEMD:-true}"

# ============== 检查 ==============
[[ $EUID -eq 0 ]] && log_error "请勿使用 root 用户运行"

echo "Moltbot 自动部署开始..."

# ============== 安装依赖 ==============
if [[ "$SKIP_DEPS" != "true" ]]; then
    log_info "安装系统依赖..."

    if ! command -v node &> /dev/null || [[ ! $(node --version) =~ ^v22 ]]; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    command -v pnpm &> /dev/null || sudo npm install -g pnpm
    command -v nginx &> /dev/null || sudo apt-get install -y nginx
    command -v git &> /dev/null || sudo apt-get install -y git

    log_success "依赖安装完成"
fi

# ============== 配置 nginx ==============
log_info "配置 nginx..."
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

# ============== 获取代码 ==============
log_info "获取代码..."
if [[ -d "$MOLTBOT_DIR/.git" ]]; then
    cd "$MOLTBOT_DIR" && git pull
else
    [[ -d "$MOLTBOT_DIR" ]] && rm -rf "$MOLTBOT_DIR"
    git clone https://github.com/moltbot/moltbot.git "$MOLTBOT_DIR"
fi
cd "$MOLTBOT_DIR"
log_success "代码获取完成"

# ============== 构建 ==============
if [[ "$SKIP_BUILD" != "true" ]]; then
    log_info "安装依赖并构建..."
    pnpm install
    pnpm build
    log_success "构建完成"
fi

# ============== 配置 Moltbot ==============
log_info "配置 Moltbot..."

pnpm moltbot config set gateway.mode local
pnpm moltbot config set gateway.auth.token "$GATEWAY_TOKEN"

if [[ -n "$DEEPSEEK_API_KEY" ]]; then
    pnpm moltbot config set providers.deepseek.apiKey "$DEEPSEEK_API_KEY"
    pnpm moltbot config set models.default "$DEEPSEEK_MODEL"
    log_success "DeepSeek 配置完成"
fi

if [[ -n "$FEISHU_APP_ID" ]] && [[ -n "$FEISHU_APP_SECRET" ]]; then
    pnpm moltbot config set channels.feishu.enabled true
    pnpm moltbot config set channels.feishu.appId "$FEISHU_APP_ID"
    pnpm moltbot config set channels.feishu.appSecret "$FEISHU_APP_SECRET"

    [[ -n "$FEISHU_VERIFICATION_TOKEN" ]] && \
        pnpm moltbot config set channels.feishu.verificationToken "$FEISHU_VERIFICATION_TOKEN"

    [[ -n "$FEISHU_ENCRYPT_KEY" ]] && \
        pnpm moltbot config set channels.feishu.encryptKey "$FEISHU_ENCRYPT_KEY"

    pnpm moltbot config set channels.feishu.webhookUrl "http://${SERVER_IP}/api/webhook/feishu"

    if [[ -n "$FEISHU_ALLOW_FROM" ]]; then
        ALLOW_FROM_JSON=$(echo "$FEISHU_ALLOW_FROM" | sed 's/ //g' | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
        pnpm moltbot config set channels.feishu.allowFrom "$ALLOW_FROM_JSON"
    fi

    pnpm moltbot config set channels.feishu.dmPolicy "$FEISHU_DM_POLICY"
    log_success "飞书配置完成"
fi

# ============== 启动服务 ==============
log_info "启动服务..."

if [[ "$USE_SYSTEMD" == "true" ]]; then
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
    sudo systemctl restart moltbot
    log_success "systemd 服务已启动"
else
    pkill -9 -f 'moltbot.*gateway' 2>/dev/null || true
    sleep 1
    nohup pnpm moltbot gateway run --bind 0.0.0.0 --port ${GATEWAY_PORT} --force > /tmp/moltbot-gateway.log 2>&1 &
    sleep 3
    pgrep -f 'moltbot.*gateway' > /dev/null && log_success "Gateway 启动成功" || log_error "Gateway 启动失败"
fi

# ============== 完成 ==============
echo ""
echo "=========================================="
echo "部署完成!"
echo "服务器: http://${SERVER_IP}"
echo "Webhook: http://${SERVER_IP}/api/webhook/feishu"
echo "Token:   ${GATEWAY_TOKEN}"
echo "=========================================="
