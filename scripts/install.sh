#!/bin/bash
#
# Moltbot 安装/配置向导
#
# 用法:
#   bash install.sh           # 正常安装
#   bash install.sh --dry-run # 测试模式 (macOS 可用)
#   DEBUG=1 bash install.sh   # 调试模式
#

DRY_RUN=false
[[ "$1" == "--dry-run" ]] && DRY_RUN=true
[[ -n "$DEBUG" ]] && set -x
$DRY_RUN || set -e

# dry-run 模式下的命令包装
run() {
    if $DRY_RUN; then
        echo -e "\033[2m[dry-run] $*\033[0m"
    else
        "$@"
    fi
}

MOLTBOT_DIR="${MOLTBOT_DIR:-$HOME/moltbot}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GITHUB_REPO="https://github.com/MindDock/moltbot.git"
GITEE_REPO="https://gitee.com/minddock/moltbot.git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info() { echo -e "${BLUE}▶${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}!${NC} $1"; }
log_err() { echo -e "${RED}✗${NC} $1"; }

get_ip() {
    curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || \
    curl -s --connect-timeout 3 ipinfo.io/ip 2>/dev/null || \
    hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
}

clear
echo -e "${CYAN}"
cat << 'EOF'
  __  __       _ _   _           _
 |  \/  | ___ | | |_| |__   ___ | |_
 | |\/| |/ _ \| | __| '_ \ / _ \| __|
 | |  | | (_) | | |_| |_) | (_) | |_
 |_|  |_|\___/|_|\__|_.__/ \___/ \__|
EOF
echo -e "${NC}"
echo -e "${DIM}智慧大脑${NC}\n"

[[ $EUID -eq 0 ]] && log_err "请使用普通用户运行 (非 root)"

SERVER_IP=$(get_ip)
echo -e "服务器 IP: ${BOLD}${SERVER_IP}${NC}\n"

# ========== 检测安装状态 ==========
NEED_INSTALL=true
NEED_BUILD=true

if [[ -d "$MOLTBOT_DIR/node_modules" ]] && [[ -d "$MOLTBOT_DIR/dist" ]]; then
    echo -e "${GREEN}检测到已安装的 Moltbot${NC} ($MOLTBOT_DIR)\n"
    NEED_INSTALL=false
    NEED_BUILD=false
elif [[ -d "$MOLTBOT_DIR" ]]; then
    echo -e "${YELLOW}检测到 Moltbot 目录但未构建${NC}\n"
    NEED_INSTALL=false
fi

# ========== 安装依赖 ==========
if $NEED_INSTALL && ! $DRY_RUN; then
    echo -e "${BOLD}[1/5] 安装系统依赖${NC}\n"

    if command -v apt-get &>/dev/null; then
        if ! command -v node &>/dev/null || [[ ! $(node -v) =~ ^v2[2-9] ]]; then
            log_info "安装 Node.js 22..."
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi
        command -v pnpm &>/dev/null || { log_info "安装 pnpm..."; sudo npm install -g pnpm; }
        command -v nginx &>/dev/null || { log_info "安装 nginx..."; sudo apt-get install -y nginx; }
        command -v git &>/dev/null || { log_info "安装 git..."; sudo apt-get install -y git; }
    elif command -v yum &>/dev/null; then
        if ! command -v node &>/dev/null || [[ ! $(node -v) =~ ^v2[2-9] ]]; then
            log_info "安装 Node.js 22..."
            curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
            sudo yum install -y nodejs
        fi
        command -v pnpm &>/dev/null || { log_info "安装 pnpm..."; sudo npm install -g pnpm; }
        command -v nginx &>/dev/null || { log_info "安装 nginx..."; sudo yum install -y nginx; }
        command -v git &>/dev/null || { log_info "安装 git..."; sudo yum install -y git; }
    else
        log_warn "未检测到 apt/yum，跳过系统依赖安装"
    fi
    log_ok "系统依赖就绪"

    echo -e "\n${BOLD}[2/5] 获取代码${NC}\n"
    log_info "克隆仓库..."
    git clone "$GITHUB_REPO" "$MOLTBOT_DIR" 2>/dev/null || git clone "$GITEE_REPO" "$MOLTBOT_DIR"
    log_ok "代码获取完成"
elif $DRY_RUN; then
    echo -e "${DIM}[dry-run] 跳过系统依赖安装和代码克隆${NC}"
fi

if ! $DRY_RUN; then
    cd "$MOLTBOT_DIR"
else
    echo -e "${DIM}[dry-run] cd $MOLTBOT_DIR${NC}"
fi

if $NEED_BUILD && ! $DRY_RUN; then
    echo -e "\n${BOLD}[3/5] 构建项目${NC}\n"
    log_info "安装依赖..."
    pnpm install
    log_info "构建主程序..."
    pnpm build
    log_info "构建管理后台 UI..."
    pnpm ui:build
    log_ok "构建完成"
elif $DRY_RUN; then
    echo -e "${DIM}[dry-run] 跳过构建${NC}"
fi

# ========== 配置 nginx ==========
echo -e "\n${BOLD}[4/5] 配置 Web 服务${NC}\n"

NGINX_CONF='server {
    listen 80;
    server_name _;

    # 管理后台 UI
    location /ui {
        proxy_pass http://127.0.0.1:18789/ui;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket 连接 (管理后台实时通信)
    location /ws {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    # Webhook (飞书/企业微信等)
    location /api/webhook/ {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    location / { return 200 OK; add_header Content-Type text/plain; }
}'

if ! $DRY_RUN; then
    if [[ -d /etc/nginx/sites-available ]]; then
        # Debian/Ubuntu
        if [[ ! -f /etc/nginx/sites-available/moltbot ]]; then
            log_info "配置 nginx..."
            echo "$NGINX_CONF" | sudo tee /etc/nginx/sites-available/moltbot >/dev/null
            sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot
            sudo rm -f /etc/nginx/sites-enabled/default
            sudo nginx -t && sudo systemctl restart nginx
        fi
    elif [[ -d /etc/nginx/conf.d ]]; then
        # CentOS/RHEL
        if [[ ! -f /etc/nginx/conf.d/moltbot.conf ]]; then
            log_info "配置 nginx..."
            echo "$NGINX_CONF" | sudo tee /etc/nginx/conf.d/moltbot.conf >/dev/null
            sudo nginx -t && sudo systemctl restart nginx
        fi
    fi
    log_ok "nginx 就绪"
else
    echo -e "${DIM}[dry-run] 跳过 nginx 配置${NC}"
fi

# ========== 交互式配置 ==========
echo -e "\n${BOLD}[5/5] 配置 Moltbot${NC}\n"

# 配置函数
cfg() {
    echo -e "${DIM}  > config set $1${NC}"
    if $DRY_RUN; then
        echo -e "${DIM}    [dry-run] pnpm moltbot config set $*${NC}"
    else
        pnpm moltbot config set "$@"
    fi
}

# Gateway
GATEWAY_TOKEN="moltbot-$(openssl rand -hex 8 2>/dev/null || date +%s)"
log_info "初始化配置..."
cfg gateway.mode local
cfg gateway.auth.token "$GATEWAY_TOKEN"
log_ok "Gateway 配置完成"

# ===== AI 提供商 =====
echo -e "${BOLD}选择 AI 提供商:${NC}"
echo "  1) DeepSeek     - 国产大模型，推荐"
echo "  2) Kimi         - 月之暗面，长文本"
echo "  3) Ollama       - 本地部署"
echo "  4) OpenAI 兼容  - 自定义 API"
echo ""
read -rp "请选择 [1-4，可多选如 1,2]: " ai_choice

IFS=',' read -ra ai_nums <<< "$ai_choice"
first_model=""

for n in "${ai_nums[@]}"; do
    n=$(echo "$n" | tr -d ' ')
    case "$n" in
        1)
            echo ""
            echo -e "${CYAN}配置 DeepSeek${NC} (https://platform.deepseek.com)"
            read -rsp "API Key: " key; echo
            if [[ -n "$key" ]]; then
                cfg providers.deepseek.apiKey "$key"
                [[ -z "$first_model" ]] && first_model="deepseek/deepseek-chat"
                log_ok "DeepSeek 已配置"
            fi
            ;;
        2)
            echo ""
            echo -e "${CYAN}配置 Kimi${NC} (https://platform.moonshot.cn)"
            read -rsp "API Key: " key; echo
            if [[ -n "$key" ]]; then
                cfg providers.moonshot.apiKey "$key"
                [[ -z "$first_model" ]] && first_model="moonshot/kimi-k2.5"
                log_ok "Kimi 已配置"
            fi
            ;;
        3)
            echo ""
            echo -e "${CYAN}配置 Ollama${NC}"
            read -rp "地址 [http://127.0.0.1:11434]: " base
            base="${base:-http://127.0.0.1:11434}"
            cfg providers.ollama.baseUrl "$base"
            log_ok "Ollama 已配置"
            ;;
        4)
            echo ""
            echo -e "${CYAN}配置 OpenAI 兼容${NC}"
            read -rp "API Base URL: " base
            read -rsp "API Key: " key; echo
            read -rp "模型名称 [gpt-3.5-turbo]: " model
            model="${model:-gpt-3.5-turbo}"
            if [[ -n "$key" ]]; then
                cfg providers.openai.baseUrl "$base"
                cfg providers.openai.apiKey "$key"
                [[ -z "$first_model" ]] && first_model="openai/$model"
                log_ok "OpenAI 兼容已配置"
            fi
            ;;
    esac
done

[[ -n "$first_model" ]] && cfg models.default "$first_model"

# ===== 通讯渠道 =====
echo ""
echo -e "${BOLD}选择通讯渠道:${NC}"
echo "  1) 飞书        - 字节跳动"
echo "  2) 企业微信    - 腾讯"
echo "  3) Telegram   - 国际"
echo "  4) Discord    - 国际"
echo "  5) Slack      - 国际"
echo "  0) 跳过"
echo ""
read -rp "请选择 [0-5，可多选如 1,2]: " ch_choice

IFS=',' read -ra ch_nums <<< "$ch_choice"

for n in "${ch_nums[@]}"; do
    n=$(echo "$n" | tr -d ' ')
    case "$n" in
        1) # 飞书
            echo ""
            echo -e "${CYAN}配置飞书${NC} (https://open.feishu.cn)"
            read -rp "App ID: " app_id
            [[ -z "$app_id" ]] && continue
            read -rsp "App Secret: " app_secret; echo
            read -rp "Verification Token: " token
            read -rp "Encrypt Key (可选，直接回车跳过): " encrypt
            read -rp "允许的 open_id (逗号分隔，留空=配对模式): " allow

            log_info "保存飞书配置..."
            cfg channels.feishu.enabled true
            cfg channels.feishu.appId "$app_id"
            cfg channels.feishu.appSecret "$app_secret"
            [[ -n "$token" ]] && cfg channels.feishu.verificationToken "$token"
            [[ -n "$encrypt" ]] && cfg channels.feishu.encryptKey "$encrypt"
            cfg channels.feishu.webhookUrl "http://${SERVER_IP}/api/webhook/feishu"

            if [[ -n "$allow" ]]; then
                allow_json=$(echo "$allow" | sed 's/ //g;s/,/","/g;s/^/["/;s/$/"]/')
                cfg channels.feishu.allowFrom "$allow_json"
                cfg channels.feishu.dmPolicy allowlist
            else
                cfg channels.feishu.dmPolicy pairing
            fi
            log_ok "飞书已配置"
            ;;
        2) # 企业微信
            echo ""
            echo -e "${CYAN}配置企业微信${NC} (https://work.weixin.qq.com)"
            read -rp "企业 ID (CorpID): " corp_id
            [[ -z "$corp_id" ]] && continue
            read -rp "应用 AgentId: " agent_id
            read -rsp "应用 Secret: " secret; echo
            read -rp "Token: " token
            read -rp "EncodingAESKey: " aes_key

            log_info "保存企业微信配置..."
            cfg channels.wecom.enabled true
            cfg channels.wecom.corpId "$corp_id"
            cfg channels.wecom.agentId "$agent_id"
            cfg channels.wecom.secret "$secret"
            [[ -n "$token" ]] && cfg channels.wecom.token "$token"
            [[ -n "$aes_key" ]] && cfg channels.wecom.encodingAesKey "$aes_key"
            cfg channels.wecom.webhookUrl "http://${SERVER_IP}/api/webhook/wecom"
            log_ok "企业微信已配置"
            ;;
        3) # Telegram
            echo ""
            echo -e "${CYAN}配置 Telegram${NC}"
            read -rsp "Bot Token: " token; echo
            [[ -z "$token" ]] && continue
            log_info "保存配置..."
            cfg channels.telegram.enabled true
            cfg channels.telegram.botToken "$token"
            log_ok "Telegram 已配置"
            ;;
        4) # Discord
            echo ""
            echo -e "${CYAN}配置 Discord${NC}"
            read -rsp "Bot Token: " token; echo
            [[ -z "$token" ]] && continue
            log_info "保存配置..."
            cfg channels.discord.enabled true
            cfg channels.discord.botToken "$token"
            log_ok "Discord 已配置"
            ;;
        5) # Slack
            echo ""
            echo -e "${CYAN}配置 Slack${NC}"
            read -rsp "Bot Token (xoxb-...): " bot_token; echo
            [[ -z "$bot_token" ]] && continue
            read -rsp "App Token (xapp-...): " app_token; echo
            log_info "保存配置..."
            cfg channels.slack.enabled true
            cfg channels.slack.botToken "$bot_token"
            [[ -n "$app_token" ]] && cfg channels.slack.appToken "$app_token"
            log_ok "Slack 已配置"
            ;;
    esac
done

# ========== 启动服务 ==========
echo ""

if ! $DRY_RUN; then
    log_info "配置系统服务..."

    sudo tee /etc/systemd/system/moltbot.service >/dev/null << SVC
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

[Install]
WantedBy=multi-user.target
SVC

    sudo systemctl daemon-reload
    sudo systemctl enable moltbot >/dev/null 2>&1
    sudo systemctl restart moltbot
    sleep 3
else
    echo -e "${DIM}[dry-run] 跳过 systemd 服务配置${NC}"
fi

# ========== 完成 ==========
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    安装完成！                          ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "服务器:  ${BOLD}http://${SERVER_IP}${NC}"
echo -e "Token:   ${GATEWAY_TOKEN}"
echo ""
echo -e "${BOLD}管理后台:${NC}"
echo -e "  访问:  ${CYAN}http://${SERVER_IP}/ui/${NC}"
echo -e "  Token: ${GATEWAY_TOKEN}"
echo ""
echo "Webhook:"
echo "  飞书:     http://${SERVER_IP}/api/webhook/feishu"
echo "  企业微信: http://${SERVER_IP}/api/webhook/wecom"
echo ""
echo "命令:"
echo "  sudo systemctl status moltbot    # 状态"
echo "  sudo journalctl -u moltbot -f    # 日志"
echo "  sudo systemctl restart moltbot   # 重启"
echo "  bash ~/moltbot/scripts/install.sh # 重新配置"
echo ""

if $DRY_RUN; then
    log_ok "[dry-run] 测试完成"
elif systemctl is-active --quiet moltbot; then
    log_ok "服务运行中"
else
    log_warn "服务可能未启动，请检查: sudo journalctl -u moltbot -n 50"
fi
