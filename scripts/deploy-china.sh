#!/bin/bash
#
# Moltbot China Deployment Script
# 用于部署 Moltbot 到国内服务器 (支持 DeepSeek + 飞书)
#
# 用法:
#   ./scripts/deploy-china.sh <server_ip> [options]
#
# 示例:
#   ./scripts/deploy-china.sh 110.40.165.230
#   ./scripts/deploy-china.sh 110.40.165.230 --skip-install
#   ./scripts/deploy-china.sh 110.40.165.230 --config-only
#

set -e

# ============== 配置区域 ==============
# 修改以下配置以匹配你的环境

# DeepSeek API
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek/deepseek-chat}"

# 飞书配置
FEISHU_APP_ID="${FEISHU_APP_ID:-}"
FEISHU_APP_SECRET="${FEISHU_APP_SECRET:-}"
FEISHU_VERIFICATION_TOKEN="${FEISHU_VERIFICATION_TOKEN:-}"
FEISHU_ENCRYPT_KEY="${FEISHU_ENCRYPT_KEY:-}"
FEISHU_ALLOW_FROM="${FEISHU_ALLOW_FROM:-}"  # 逗号分隔的 open_id 列表

# Gateway 配置
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-moltbot-$(openssl rand -hex 8)}"

# SSH 配置
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"  # 可选: SSH 私钥路径

# ============== 脚本开始 ==============

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 解析参数
SERVER_IP=""
SKIP_INSTALL=false
CONFIG_ONLY=false
SYNC_ONLY=false
RESTART_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --sync-only)
            SYNC_ONLY=true
            shift
            ;;
        --restart-only)
            RESTART_ONLY=true
            shift
            ;;
        --help|-h)
            echo "用法: $0 <server_ip> [options]"
            echo ""
            echo "选项:"
            echo "  --skip-install   跳过系统依赖安装 (Node.js, pnpm, nginx)"
            echo "  --config-only    仅更新配置，不同步代码"
            echo "  --sync-only      仅同步代码，不重启服务"
            echo "  --restart-only   仅重启 gateway 服务"
            echo ""
            echo "环境变量:"
            echo "  DEEPSEEK_API_KEY          DeepSeek API 密钥"
            echo "  FEISHU_APP_ID             飞书 App ID"
            echo "  FEISHU_APP_SECRET         飞书 App Secret"
            echo "  FEISHU_VERIFICATION_TOKEN 飞书验证令牌"
            echo "  FEISHU_ALLOW_FROM         允许的飞书用户 (逗号分隔)"
            echo "  GATEWAY_PORT              Gateway 端口 (默认: 18789)"
            echo "  GATEWAY_TOKEN             Gateway 认证令牌"
            echo "  SSH_USER                  SSH 用户名 (默认: ubuntu)"
            echo "  SSH_KEY                   SSH 私钥路径"
            exit 0
            ;;
        -*)
            log_error "未知选项: $1"
            exit 1
            ;;
        *)
            SERVER_IP="$1"
            shift
            ;;
    esac
done

if [[ -z "$SERVER_IP" ]]; then
    log_error "请提供服务器 IP 地址"
    echo "用法: $0 <server_ip> [options]"
    exit 1
fi

# SSH 命令构建
SSH_OPTS="-o ConnectTimeout=30 -o ServerAliveInterval=30 -o StrictHostKeyChecking=accept-new"
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi
SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SERVER_IP}"
SCP_CMD="scp $SSH_OPTS"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info "Moltbot China Deployment"
log_info "服务器: ${SSH_USER}@${SERVER_IP}"
log_info "项目目录: $PROJECT_DIR"
echo ""

# 检查服务器连接
check_connection() {
    log_info "检查服务器连接..."
    if ! $SSH_CMD "echo 'connected'" > /dev/null 2>&1; then
        log_error "无法连接到服务器 $SERVER_IP"
        exit 1
    fi
    log_success "服务器连接正常"
}

# 安装系统依赖
install_dependencies() {
    if $SKIP_INSTALL; then
        log_warn "跳过系统依赖安装"
        return
    fi

    log_info "安装系统依赖..."

    # Node.js 22
    log_info "检查 Node.js..."
    NODE_VERSION=$($SSH_CMD "node --version 2>/dev/null || echo 'none'")
    if [[ "$NODE_VERSION" == "none" ]] || [[ ! "$NODE_VERSION" =~ ^v22 ]]; then
        log_info "安装 Node.js 22..."
        $SSH_CMD "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs"
        log_success "Node.js 22 已安装"
    else
        log_success "Node.js 已安装: $NODE_VERSION"
    fi

    # pnpm
    log_info "检查 pnpm..."
    PNPM_VERSION=$($SSH_CMD "pnpm --version 2>/dev/null || echo 'none'")
    if [[ "$PNPM_VERSION" == "none" ]]; then
        log_info "安装 pnpm..."
        $SSH_CMD "sudo npm install -g pnpm"
        log_success "pnpm 已安装"
    else
        log_success "pnpm 已安装: $PNPM_VERSION"
    fi

    # nginx
    log_info "检查 nginx..."
    NGINX_VERSION=$($SSH_CMD "nginx -v 2>&1 || echo 'none'")
    if [[ "$NGINX_VERSION" == "none" ]]; then
        log_info "安装 nginx..."
        $SSH_CMD "sudo apt-get install -y nginx"
        log_success "nginx 已安装"
    else
        log_success "nginx 已安装"
    fi
}

# 配置 nginx
configure_nginx() {
    log_info "配置 nginx..."

    $SSH_CMD "sudo tee /etc/nginx/sites-available/moltbot > /dev/null" << EOF
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

    $SSH_CMD "sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot && \
              sudo rm -f /etc/nginx/sites-enabled/default && \
              sudo nginx -t && \
              sudo systemctl restart nginx"

    log_success "nginx 配置完成"
}

# 同步代码
sync_code() {
    if $CONFIG_ONLY || $RESTART_ONLY; then
        log_warn "跳过代码同步"
        return
    fi

    log_info "同步代码到服务器..."
    rsync -avz --progress \
        --exclude='node_modules' \
        --exclude='dist' \
        --exclude='.git' \
        --exclude='.env' \
        --exclude='*.log' \
        -e "ssh $SSH_OPTS" \
        "$PROJECT_DIR/" \
        "${SSH_USER}@${SERVER_IP}:~/moltbot/"

    log_success "代码同步完成"
}

# 安装项目依赖并构建
build_project() {
    if $CONFIG_ONLY || $RESTART_ONLY; then
        log_warn "跳过项目构建"
        return
    fi

    log_info "安装项目依赖..."
    $SSH_CMD "cd ~/moltbot && pnpm install"
    log_success "依赖安装完成"

    log_info "构建项目..."
    $SSH_CMD "cd ~/moltbot && pnpm build"
    log_success "项目构建完成"
}

# 配置 Moltbot
configure_moltbot() {
    if $SYNC_ONLY; then
        log_warn "跳过配置"
        return
    fi

    log_info "配置 Moltbot..."

    # Gateway 配置
    log_info "配置 Gateway..."
    $SSH_CMD "cd ~/moltbot && pnpm moltbot config set gateway.mode local"
    $SSH_CMD "cd ~/moltbot && pnpm moltbot config set gateway.auth.token '$GATEWAY_TOKEN'"

    # DeepSeek 配置
    if [[ -n "$DEEPSEEK_API_KEY" ]]; then
        log_info "配置 DeepSeek..."
        $SSH_CMD "cd ~/moltbot && pnpm moltbot config set providers.deepseek.apiKey '$DEEPSEEK_API_KEY'"
        $SSH_CMD "cd ~/moltbot && pnpm moltbot config set models.default '$DEEPSEEK_MODEL'"
        log_success "DeepSeek 配置完成"
    else
        log_warn "未提供 DEEPSEEK_API_KEY，跳过 DeepSeek 配置"
    fi

    # 飞书配置
    if [[ -n "$FEISHU_APP_ID" ]] && [[ -n "$FEISHU_APP_SECRET" ]]; then
        log_info "配置飞书..."
        $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.enabled true"
        $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.appId '$FEISHU_APP_ID'"
        $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.appSecret '$FEISHU_APP_SECRET'"

        if [[ -n "$FEISHU_VERIFICATION_TOKEN" ]]; then
            $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.verificationToken '$FEISHU_VERIFICATION_TOKEN'"
        fi

        if [[ -n "$FEISHU_ENCRYPT_KEY" ]]; then
            $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.encryptKey '$FEISHU_ENCRYPT_KEY'"
        fi

        $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.webhookUrl 'http://${SERVER_IP}/api/webhook/feishu'"

        if [[ -n "$FEISHU_ALLOW_FROM" ]]; then
            # 转换逗号分隔为 JSON 数组
            ALLOW_FROM_JSON=$(echo "$FEISHU_ALLOW_FROM" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
            $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.allowFrom '$ALLOW_FROM_JSON'"
            $SSH_CMD "cd ~/moltbot && pnpm moltbot config set channels.feishu.dmPolicy 'allowlist'"
        fi

        log_success "飞书配置完成"
    else
        log_warn "未提供飞书凭据，跳过飞书配置"
    fi

    log_success "Moltbot 配置完成"
}

# 启动 Gateway
start_gateway() {
    log_info "启动 Gateway..."

    $SSH_CMD "pkill -9 -f 'moltbot.*gateway' || true"
    sleep 2

    $SSH_CMD "cd ~/moltbot && nohup pnpm moltbot gateway run --bind 0.0.0.0 --port ${GATEWAY_PORT} --force > /tmp/moltbot-gateway.log 2>&1 &"
    sleep 3

    # 检查是否启动成功
    if $SSH_CMD "pgrep -f 'moltbot.*gateway' > /dev/null"; then
        log_success "Gateway 启动成功"
    else
        log_error "Gateway 启动失败"
        log_info "查看日志: ssh ${SSH_USER}@${SERVER_IP} 'tail -50 /tmp/moltbot-gateway.log'"
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证部署..."

    # 检查 HTTP
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://${SERVER_IP}/" 2>/dev/null || echo "000")
    if [[ "$HTTP_STATUS" == "200" ]]; then
        log_success "HTTP 服务正常"
    else
        log_warn "HTTP 状态码: $HTTP_STATUS"
    fi

    # 检查 Gateway 端口
    if $SSH_CMD "ss -ltnp | grep -q ':${GATEWAY_PORT}'"; then
        log_success "Gateway 端口 ${GATEWAY_PORT} 正在监听"
    else
        log_warn "Gateway 端口 ${GATEWAY_PORT} 未监听"
    fi

    echo ""
    log_success "部署完成!"
    echo ""
    echo "=========================================="
    echo "服务器地址: http://${SERVER_IP}"
    echo "飞书 Webhook: http://${SERVER_IP}/api/webhook/feishu"
    echo "Gateway Token: $GATEWAY_TOKEN"
    echo ""
    echo "常用命令:"
    echo "  查看日志: ssh ${SSH_USER}@${SERVER_IP} 'tail -f /tmp/moltbot-gateway.log'"
    echo "  重启服务: ssh ${SSH_USER}@${SERVER_IP} 'cd ~/moltbot && pkill -9 -f moltbot-gateway; nohup pnpm moltbot gateway run --bind 0.0.0.0 --port ${GATEWAY_PORT} --force > /tmp/moltbot-gateway.log 2>&1 &'"
    echo "  检查状态: ssh ${SSH_USER}@${SERVER_IP} 'cd ~/moltbot && pnpm moltbot channels status --probe'"
    echo "=========================================="
}

# 主流程
main() {
    check_connection

    if $RESTART_ONLY; then
        start_gateway
        verify_deployment
        exit 0
    fi

    install_dependencies
    configure_nginx
    sync_code
    build_project
    configure_moltbot
    start_gateway
    verify_deployment
}

main
