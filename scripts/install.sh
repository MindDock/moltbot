#!/bin/bash
#
# Moltbot 安装向导
# 智能聊天机器人一键部署
#
# 用法: bash install.sh
#

set -e

# ============== 配置 ==============
INSTALLER_VERSION="1.0.0"
GITHUB_REPO="https://github.com/MindDock/moltbot.git"
GITEE_REPO="https://gitee.com/minddock/moltbot.git"  # 国内镜像
MOLTBOT_DIR="${MOLTBOT_DIR:-$HOME/moltbot}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"

# ============== 样式 ==============
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
log_step() { echo -e "\n${BOLD}${CYAN}[$1]${NC}\n"; }

prompt() {
    local msg="$1" default="$2" secret="$3" val
    [[ -n "$default" ]] && msg="$msg [$default]"
    if [[ "$secret" == "1" ]]; then
        read -rsp "$msg: " val; echo
    else
        read -rp "$msg: " val
    fi
    echo "${val:-$default}"
}

confirm() {
    local msg="$1" default="${2:-y}"
    [[ "$default" == "y" ]] && read -rp "$msg [Y/n]: " yn || read -rp "$msg [y/N]: " yn
    yn="${yn:-$default}"
    [[ "$yn" =~ ^[Yy] ]]
}

get_ip() {
    curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || \
    curl -s --connect-timeout 3 ipinfo.io/ip 2>/dev/null || \
    hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
}

# ============== Logo ==============
print_logo() {
    echo -e "${CYAN}"
    cat << 'EOF'
  __  __       _ _   _           _
 |  \/  | ___ | | |_| |__   ___ | |_
 | |\/| |/ _ \| | __| '_ \ / _ \| __|
 | |  | | (_) | | |_| |_) | (_) | |_
 |_|  |_|\___/|_|\__|_.__/ \___/ \__|
EOF
    echo -e "${NC}"
    echo -e "${DIM}智能聊天机器人平台 · MindDock${NC}\n"
}

# ============== 主流程 ==============
main() {
    clear
    print_logo

    [[ $EUID -eq 0 ]] && { log_err "请使用普通用户运行 (非 root)"; exit 1; }

    SERVER_IP=$(get_ip)
    GATEWAY_TOKEN="moltbot-$(openssl rand -hex 8 2>/dev/null || date +%s)"

    # 临时保存配置
    declare -A CONFIG
    declare -a AI_LIST CHANNEL_LIST

    # ==================== 选择 AI ====================
    log_step "1/4 选择 AI 提供商"
    echo -e "${DIM}选择用于驱动机器人的 AI 模型服务${NC}\n"

    echo "  1. DeepSeek      - 国产大模型，性价比高，推荐"
    echo "  2. Kimi (月之暗面) - 长文本能力强，支持联网搜索"
    echo "  3. Ollama        - 本地部署，隐私安全，需自行安装"
    echo "  4. OpenAI 兼容   - 支持任意 OpenAI API 兼容服务"
    echo ""

    read -rp "请选择 (可多选，如 1,2): " ai_choice
    IFS=',' read -ra ai_nums <<< "$ai_choice"

    for n in "${ai_nums[@]}"; do
        n=$(echo "$n" | tr -d ' ')
        case "$n" in
            1)
                echo -e "\n${BOLD}配置 DeepSeek${NC}"
                echo -e "${DIM}获取 API Key: https://platform.deepseek.com${NC}"
                key=$(prompt "API Key" "" 1)
                if [[ -n "$key" ]]; then
                    CONFIG[DEEPSEEK_API_KEY]="$key"
                    AI_LIST+=("deepseek")
                    log_ok "DeepSeek 已配置"
                fi
                ;;
            2)
                echo -e "\n${BOLD}配置 Kimi${NC}"
                echo -e "${DIM}获取 API Key: https://platform.moonshot.cn${NC}"
                key=$(prompt "API Key" "" 1)
                if [[ -n "$key" ]]; then
                    CONFIG[MOONSHOT_API_KEY]="$key"
                    AI_LIST+=("moonshot")
                    log_ok "Kimi 已配置"
                fi
                ;;
            3)
                echo -e "\n${BOLD}配置 Ollama${NC}"
                echo -e "${DIM}确保 Ollama 服务已运行在本地${NC}"
                base=$(prompt "Ollama 地址" "http://127.0.0.1:11434")
                CONFIG[OLLAMA_BASE_URL]="$base"
                AI_LIST+=("ollama")
                log_ok "Ollama 已配置"
                ;;
            4)
                echo -e "\n${BOLD}配置 OpenAI 兼容服务${NC}"
                base=$(prompt "API Base URL" "https://api.example.com/v1")
                key=$(prompt "API Key" "" 1)
                model=$(prompt "模型名称" "gpt-3.5-turbo")
                if [[ -n "$key" ]]; then
                    CONFIG[OPENAI_BASE_URL]="$base"
                    CONFIG[OPENAI_API_KEY]="$key"
                    CONFIG[OPENAI_MODEL]="$model"
                    AI_LIST+=("openai")
                    log_ok "OpenAI 兼容已配置"
                fi
                ;;
        esac
    done

    [[ ${#AI_LIST[@]} -eq 0 ]] && { log_err "请至少选择一个 AI 提供商"; exit 1; }

    # ==================== 选择渠道 ====================
    log_step "2/4 选择通讯渠道"
    echo -e "${DIM}选择要接入的即时通讯平台${NC}\n"

    echo "  1. 飞书 (Feishu)     - 字节跳动企业协作平台"
    echo "  2. 企业微信 (WeCom)  - 腾讯企业微信"
    echo "  3. Telegram         - 国际即时通讯 (需代理)"
    echo "  4. Discord          - 游戏社区平台 (需代理)"
    echo "  5. Slack            - 企业协作工具 (需代理)"
    echo "  0. 跳过             - 仅通过 API 使用"
    echo ""

    read -rp "请选择 (可多选，如 1,2): " ch_choice
    IFS=',' read -ra ch_nums <<< "$ch_choice"

    for n in "${ch_nums[@]}"; do
        n=$(echo "$n" | tr -d ' ')
        case "$n" in
            1) # 飞书
                echo -e "\n${BOLD}配置飞书${NC}"
                echo -e "${DIM}前往 https://open.feishu.cn 创建应用${NC}"
                app_id=$(prompt "App ID")
                [[ -z "$app_id" ]] && continue
                app_secret=$(prompt "App Secret" "" 1)
                token=$(prompt "Verification Token (事件订阅)")
                encrypt=$(prompt "Encrypt Key (可选)")
                allow=$(prompt "允许的用户 open_id (逗号分隔，留空=配对模式)")
                CONFIG[FEISHU_APP_ID]="$app_id"
                CONFIG[FEISHU_APP_SECRET]="$app_secret"
                CONFIG[FEISHU_VERIFICATION_TOKEN]="$token"
                CONFIG[FEISHU_ENCRYPT_KEY]="$encrypt"
                CONFIG[FEISHU_ALLOW_FROM]="$allow"
                CHANNEL_LIST+=("feishu")
                log_ok "飞书已配置"
                ;;
            2) # 企业微信
                echo -e "\n${BOLD}配置企业微信${NC}"
                echo -e "${DIM}前往 https://work.weixin.qq.com 创建应用${NC}"
                corp_id=$(prompt "企业 ID (CorpID)")
                [[ -z "$corp_id" ]] && continue
                agent_id=$(prompt "应用 AgentId")
                secret=$(prompt "应用 Secret" "" 1)
                token=$(prompt "Token (接收消息)")
                aes_key=$(prompt "EncodingAESKey")
                CONFIG[WECOM_CORP_ID]="$corp_id"
                CONFIG[WECOM_AGENT_ID]="$agent_id"
                CONFIG[WECOM_SECRET]="$secret"
                CONFIG[WECOM_TOKEN]="$token"
                CONFIG[WECOM_AES_KEY]="$aes_key"
                CHANNEL_LIST+=("wecom")
                log_ok "企业微信已配置"
                ;;
            3) # Telegram
                echo -e "\n${BOLD}配置 Telegram${NC}"
                echo -e "${DIM}通过 @BotFather 创建机器人${NC}"
                token=$(prompt "Bot Token" "" 1)
                [[ -z "$token" ]] && continue
                CONFIG[TELEGRAM_BOT_TOKEN]="$token"
                CHANNEL_LIST+=("telegram")
                log_ok "Telegram 已配置"
                ;;
            4) # Discord
                echo -e "\n${BOLD}配置 Discord${NC}"
                echo -e "${DIM}前往 https://discord.com/developers 创建应用${NC}"
                token=$(prompt "Bot Token" "" 1)
                [[ -z "$token" ]] && continue
                CONFIG[DISCORD_BOT_TOKEN]="$token"
                CHANNEL_LIST+=("discord")
                log_ok "Discord 已配置"
                ;;
            5) # Slack
                echo -e "\n${BOLD}配置 Slack${NC}"
                echo -e "${DIM}前往 https://api.slack.com/apps 创建应用${NC}"
                bot_token=$(prompt "Bot Token (xoxb-...)" "" 1)
                [[ -z "$bot_token" ]] && continue
                app_token=$(prompt "App Token (xapp-...)" "" 1)
                CONFIG[SLACK_BOT_TOKEN]="$bot_token"
                CONFIG[SLACK_APP_TOKEN]="$app_token"
                CHANNEL_LIST+=("slack")
                log_ok "Slack 已配置"
                ;;
        esac
    done

    # ==================== 确认 ====================
    log_step "3/4 确认配置"

    echo "服务器 IP:   $SERVER_IP"
    echo "AI 提供商:   ${AI_LIST[*]:-无}"
    echo "通讯渠道:    ${CHANNEL_LIST[*]:-无}"
    echo "安装目录:    $MOLTBOT_DIR"
    echo ""

    confirm "确认开始安装?" || { log_info "已取消"; exit 0; }

    # ==================== 安装 ====================
    log_step "4/4 开始安装"

    # 安装依赖
    log_info "安装系统依赖..."
    if command -v apt-get &>/dev/null; then
        if ! command -v node &>/dev/null || [[ ! $(node -v) =~ ^v2[2-9] ]]; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi
        command -v pnpm &>/dev/null || sudo npm install -g pnpm
        command -v nginx &>/dev/null || sudo apt-get install -y nginx
        command -v git &>/dev/null || sudo apt-get install -y git
    elif command -v yum &>/dev/null; then
        if ! command -v node &>/dev/null || [[ ! $(node -v) =~ ^v2[2-9] ]]; then
            curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
            sudo yum install -y nodejs
        fi
        command -v pnpm &>/dev/null || sudo npm install -g pnpm
        command -v nginx &>/dev/null || sudo yum install -y nginx
        command -v git &>/dev/null || sudo yum install -y git
    else
        log_err "不支持的系统，请手动安装 Node.js 22, pnpm, nginx, git"
        exit 1
    fi
    log_ok "依赖安装完成"

    # 配置 nginx
    log_info "配置 nginx..."
    sudo tee /etc/nginx/sites-available/moltbot >/dev/null 2>&1 || \
    sudo tee /etc/nginx/conf.d/moltbot.conf >/dev/null << NGINX
server {
    listen 80;
    server_name _;
    location /api/webhook/ {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
NGINX
    [[ -d /etc/nginx/sites-enabled ]] && {
        sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot
        sudo rm -f /etc/nginx/sites-enabled/default
    }
    sudo nginx -t && sudo systemctl restart nginx
    log_ok "nginx 配置完成"

    # 克隆代码
    log_info "获取代码..."
    if [[ -d "$MOLTBOT_DIR/.git" ]]; then
        cd "$MOLTBOT_DIR" && git pull
    else
        [[ -d "$MOLTBOT_DIR" ]] && mv "$MOLTBOT_DIR" "${MOLTBOT_DIR}.bak.$(date +%s)"
        # 优先尝试 GitHub，失败则用 Gitee
        git clone "$GITHUB_REPO" "$MOLTBOT_DIR" 2>/dev/null || \
        git clone "$GITEE_REPO" "$MOLTBOT_DIR"
    fi
    cd "$MOLTBOT_DIR"
    log_ok "代码获取完成"

    # 构建
    log_info "安装依赖并构建 (可能需要几分钟)..."
    pnpm install
    pnpm build
    log_ok "构建完成"

    # 应用配置
    log_info "应用配置..."
    pnpm moltbot config set gateway.mode local
    pnpm moltbot config set gateway.auth.token "$GATEWAY_TOKEN"

    # AI 配置
    local first_model=""
    for ai in "${AI_LIST[@]}"; do
        case "$ai" in
            deepseek)
                pnpm moltbot config set providers.deepseek.apiKey "${CONFIG[DEEPSEEK_API_KEY]}"
                [[ -z "$first_model" ]] && first_model="deepseek/deepseek-chat"
                ;;
            moonshot)
                pnpm moltbot config set providers.moonshot.apiKey "${CONFIG[MOONSHOT_API_KEY]}"
                [[ -z "$first_model" ]] && first_model="moonshot/kimi-k2.5"
                ;;
            ollama)
                pnpm moltbot config set providers.ollama.baseUrl "${CONFIG[OLLAMA_BASE_URL]}"
                ;;
            openai)
                pnpm moltbot config set providers.openai.baseUrl "${CONFIG[OPENAI_BASE_URL]}"
                pnpm moltbot config set providers.openai.apiKey "${CONFIG[OPENAI_API_KEY]}"
                [[ -z "$first_model" ]] && first_model="openai/${CONFIG[OPENAI_MODEL]}"
                ;;
        esac
    done
    [[ -n "$first_model" ]] && pnpm moltbot config set models.default "$first_model"

    # 渠道配置
    for ch in "${CHANNEL_LIST[@]}"; do
        case "$ch" in
            feishu)
                pnpm moltbot config set channels.feishu.enabled true
                pnpm moltbot config set channels.feishu.appId "${CONFIG[FEISHU_APP_ID]}"
                pnpm moltbot config set channels.feishu.appSecret "${CONFIG[FEISHU_APP_SECRET]}"
                [[ -n "${CONFIG[FEISHU_VERIFICATION_TOKEN]}" ]] && \
                    pnpm moltbot config set channels.feishu.verificationToken "${CONFIG[FEISHU_VERIFICATION_TOKEN]}"
                [[ -n "${CONFIG[FEISHU_ENCRYPT_KEY]}" ]] && \
                    pnpm moltbot config set channels.feishu.encryptKey "${CONFIG[FEISHU_ENCRYPT_KEY]}"
                pnpm moltbot config set channels.feishu.webhookUrl "http://${SERVER_IP}/api/webhook/feishu"
                if [[ -n "${CONFIG[FEISHU_ALLOW_FROM]}" ]]; then
                    allow_json=$(echo "${CONFIG[FEISHU_ALLOW_FROM]}" | sed 's/ //g;s/,/","/g;s/^/["/;s/$/"]/')
                    pnpm moltbot config set channels.feishu.allowFrom "$allow_json"
                    pnpm moltbot config set channels.feishu.dmPolicy allowlist
                else
                    pnpm moltbot config set channels.feishu.dmPolicy pairing
                fi
                ;;
            wecom)
                pnpm moltbot config set channels.wecom.enabled true
                pnpm moltbot config set channels.wecom.corpId "${CONFIG[WECOM_CORP_ID]}"
                pnpm moltbot config set channels.wecom.agentId "${CONFIG[WECOM_AGENT_ID]}"
                pnpm moltbot config set channels.wecom.secret "${CONFIG[WECOM_SECRET]}"
                [[ -n "${CONFIG[WECOM_TOKEN]}" ]] && pnpm moltbot config set channels.wecom.token "${CONFIG[WECOM_TOKEN]}"
                [[ -n "${CONFIG[WECOM_AES_KEY]}" ]] && pnpm moltbot config set channels.wecom.encodingAesKey "${CONFIG[WECOM_AES_KEY]}"
                pnpm moltbot config set channels.wecom.webhookUrl "http://${SERVER_IP}/api/webhook/wecom"
                ;;
            telegram)
                pnpm moltbot config set channels.telegram.enabled true
                pnpm moltbot config set channels.telegram.botToken "${CONFIG[TELEGRAM_BOT_TOKEN]}"
                ;;
            discord)
                pnpm moltbot config set channels.discord.enabled true
                pnpm moltbot config set channels.discord.botToken "${CONFIG[DISCORD_BOT_TOKEN]}"
                ;;
            slack)
                pnpm moltbot config set channels.slack.enabled true
                pnpm moltbot config set channels.slack.botToken "${CONFIG[SLACK_BOT_TOKEN]}"
                [[ -n "${CONFIG[SLACK_APP_TOKEN]}" ]] && pnpm moltbot config set channels.slack.appToken "${CONFIG[SLACK_APP_TOKEN]}"
                ;;
        esac
    done
    log_ok "配置应用完成"

    # 创建服务
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
    sudo systemctl enable moltbot
    sudo systemctl start moltbot
    sleep 3
    systemctl is-active --quiet moltbot && log_ok "服务启动成功" || log_warn "服务启动可能失败，请检查日志"

    # 完成
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                      安装完成！                            ${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "服务器:       ${BOLD}http://${SERVER_IP}${NC}"
    echo -e "Gateway:      http://127.0.0.1:${GATEWAY_PORT}"
    echo -e "Token:        ${GATEWAY_TOKEN}"
    echo ""
    [[ ${#CHANNEL_LIST[@]} -gt 0 ]] && {
        echo "Webhook 地址:"
        for ch in "${CHANNEL_LIST[@]}"; do
            echo "  $ch: http://${SERVER_IP}/api/webhook/${ch}"
        done
        echo ""
    }
    echo "常用命令:"
    echo "  sudo systemctl status moltbot   # 查看状态"
    echo "  sudo journalctl -u moltbot -f   # 查看日志"
    echo "  sudo systemctl restart moltbot  # 重启服务"
    echo ""
}

main "$@"
