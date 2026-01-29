#!/bin/bash
#
# Moltbot 安装向导
# 智能聊天机器人部署脚本
#
# 用法: curl -fsSL https://install.molt.bot/china | bash
#

set -e

# ============== 版本信息 ==============
INSTALLER_VERSION="1.0.0"
MOLTBOT_REPO="https://github.com/moltbot/moltbot.git"
MOLTBOT_DIR="${MOLTBOT_DIR:-$HOME/moltbot}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"

# ============== 颜色和样式 ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============== 工具函数 ==============
print_logo() {
    echo -e "${CYAN}"
    echo "  __  __       _ _   _           _   "
    echo " |  \/  | ___ | | |_| |__   ___ | |_ "
    echo " | |\/| |/ _ \| | __| '_ \ / _ \| __|"
    echo " | |  | | (_) | | |_| |_) | (_) | |_ "
    echo " |_|  |_|\___/|_|\__|_.__/ \___/ \__|"
    echo -e "${NC}"
    echo -e "${DIM}智能聊天机器人平台 v${INSTALLER_VERSION}${NC}"
    echo ""
}

log_info() { echo -e "${BLUE}[信息]${NC} $1"; }
log_success() { echo -e "${GREEN}[完成]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; }
log_step() { echo -e "\n${BOLD}${CYAN}>>> $1${NC}\n"; }

# 显示菜单并获取选择
show_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=()
    local current=0
    local total=${#options[@]}

    echo -e "\n${BOLD}$title${NC} ${DIM}(空格选择, 回车确认)${NC}\n"

    for i in "${!options[@]}"; do
        echo "  [ ] ${options[$i]}"
    done

    echo ""
    read -p "请输入选项编号 (多选用逗号分隔, 如 1,2,3): " choices

    if [[ -z "$choices" ]]; then
        echo ""
        return
    fi

    IFS=',' read -ra nums <<< "$choices"
    for num in "${nums[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= total )); then
            selected+=("${options[$((num-1))]}")
        fi
    done

    printf '%s\n' "${selected[@]}"
}

# 显示单选菜单
show_single_menu() {
    local title="$1"
    shift
    local options=("$@")
    local total=${#options[@]}

    echo -e "\n${BOLD}$title${NC}\n"

    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done

    echo ""
    read -p "请选择 [1-$total]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
        echo "${options[$((choice-1))]}"
    else
        echo "${options[0]}"
    fi
}

# 获取输入
prompt_input() {
    local message="$1"
    local default="$2"
    local is_secret="$3"
    local value

    if [[ -n "$default" ]]; then
        message="$message [${default}]"
    fi

    if [[ "$is_secret" == "true" ]]; then
        read -sp "$message: " value
        echo ""
    else
        read -p "$message: " value
    fi

    if [[ -z "$value" ]] && [[ -n "$default" ]]; then
        value="$default"
    fi

    echo "$value"
}

# 确认
confirm() {
    local message="$1"
    local default="${2:-y}"
    local yn

    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -p "$message [y/N]: " yn
        yn="${yn:-n}"
    fi

    [[ "$yn" =~ ^[Yy] ]]
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 获取服务器公网 IP
get_public_ip() {
    curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
    curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    echo "localhost"
}

# ============== AI 提供商配置 ==============
declare -A AI_PROVIDERS
AI_PROVIDERS=(
    ["DeepSeek"]="deepseek|https://api.deepseek.com|deepseek-chat|国产大模型,性价比高"
    ["Kimi (月之暗面)"]="kimi|https://api.moonshot.cn/v1|moonshot-v1-8k|国产大模型,长文本能力强"
    ["通义千问"]="qwen|https://dashscope.aliyuncs.com/compatible-mode/v1|qwen-turbo|阿里云,企业级服务"
    ["智谱 GLM"]="zhipu|https://open.bigmodel.cn/api/paas/v4|glm-4|清华系,学术背景"
    ["OpenAI"]="openai|https://api.openai.com/v1|gpt-4o-mini|需要海外网络"
    ["OpenAI 兼容"]="openai-compatible|自定义|自定义|兼容 OpenAI API 的服务"
)

configure_ai_provider() {
    local provider_name="$1"
    local provider_info="${AI_PROVIDERS[$provider_name]}"

    IFS='|' read -r provider_id base_url default_model description <<< "$provider_info"

    echo -e "\n${BOLD}配置 $provider_name${NC} ${DIM}($description)${NC}\n"

    local api_key
    api_key=$(prompt_input "API Key" "" "true")

    if [[ -z "$api_key" ]]; then
        log_warn "跳过 $provider_name 配置"
        return 1
    fi

    local custom_base_url="$base_url"
    local custom_model="$default_model"

    if [[ "$provider_id" == "openai-compatible" ]]; then
        custom_base_url=$(prompt_input "API Base URL" "https://api.example.com/v1")
        custom_model=$(prompt_input "模型名称" "gpt-3.5-turbo")
        provider_id="openai"  # 使用 OpenAI 兼容模式
    fi

    # 保存配置
    echo "PROVIDER_${provider_id^^}_API_KEY='$api_key'" >> "$CONFIG_FILE"
    echo "PROVIDER_${provider_id^^}_BASE_URL='$custom_base_url'" >> "$CONFIG_FILE"
    echo "PROVIDER_${provider_id^^}_MODEL='$custom_model'" >> "$CONFIG_FILE"

    # 记录已配置的提供商
    CONFIGURED_PROVIDERS+=("$provider_id")

    log_success "$provider_name 配置完成"
    return 0
}

# ============== 通讯渠道配置 ==============
declare -A CHANNELS
CHANNELS=(
    ["飞书 (Feishu)"]="feishu|企业协作平台,字节跳动旗下"
    ["企业微信 (WeCom)"]="wecom|腾讯企业通讯工具"
    ["钉钉 (DingTalk)"]="dingtalk|阿里企业通讯平台"
    ["Telegram"]="telegram|国际即时通讯,需要代理"
    ["Discord"]="discord|游戏社区平台,需要代理"
    ["Slack"]="slack|企业协作工具,国际版"
)

configure_channel_feishu() {
    echo -e "\n${BOLD}配置飞书${NC}\n"
    echo -e "${DIM}请前往 https://open.feishu.cn 创建应用${NC}\n"

    local app_id app_secret verification_token encrypt_key allow_from

    app_id=$(prompt_input "App ID (应用凭证)")
    if [[ -z "$app_id" ]]; then
        log_warn "跳过飞书配置"
        return 1
    fi

    app_secret=$(prompt_input "App Secret" "" "true")
    verification_token=$(prompt_input "Verification Token (事件订阅)")
    encrypt_key=$(prompt_input "Encrypt Key (可选, 消息加密)")

    echo ""
    log_info "允许访问的用户 open_id"
    echo -e "${DIM}  - 留空表示需要配对验证 (推荐)${NC}"
    echo -e "${DIM}  - 输入 * 表示允许所有用户${NC}"
    echo -e "${DIM}  - 多个用户用逗号分隔${NC}"
    allow_from=$(prompt_input "允许的用户")

    cat >> "$CONFIG_FILE" << EOF

# 飞书配置
FEISHU_ENABLED=true
FEISHU_APP_ID='$app_id'
FEISHU_APP_SECRET='$app_secret'
FEISHU_VERIFICATION_TOKEN='$verification_token'
FEISHU_ENCRYPT_KEY='$encrypt_key'
FEISHU_ALLOW_FROM='$allow_from'
EOF

    CONFIGURED_CHANNELS+=("feishu")
    log_success "飞书配置完成"
}

configure_channel_wecom() {
    echo -e "\n${BOLD}配置企业微信${NC}\n"
    echo -e "${DIM}请前往 https://work.weixin.qq.com 创建应用${NC}\n"

    local corp_id agent_id secret token encoding_aes_key

    corp_id=$(prompt_input "企业 ID (CorpID)")
    if [[ -z "$corp_id" ]]; then
        log_warn "跳过企业微信配置"
        return 1
    fi

    agent_id=$(prompt_input "应用 AgentId")
    secret=$(prompt_input "应用 Secret" "" "true")
    token=$(prompt_input "Token (接收消息)")
    encoding_aes_key=$(prompt_input "EncodingAESKey (消息加密)")

    cat >> "$CONFIG_FILE" << EOF

# 企业微信配置
WECOM_ENABLED=true
WECOM_CORP_ID='$corp_id'
WECOM_AGENT_ID='$agent_id'
WECOM_SECRET='$secret'
WECOM_TOKEN='$token'
WECOM_ENCODING_AES_KEY='$encoding_aes_key'
EOF

    CONFIGURED_CHANNELS+=("wecom")
    log_success "企业微信配置完成"
}

configure_channel_dingtalk() {
    echo -e "\n${BOLD}配置钉钉${NC}\n"
    echo -e "${DIM}请前往 https://open.dingtalk.com 创建应用${NC}\n"

    local app_key app_secret robot_code

    app_key=$(prompt_input "AppKey")
    if [[ -z "$app_key" ]]; then
        log_warn "跳过钉钉配置"
        return 1
    fi

    app_secret=$(prompt_input "AppSecret" "" "true")
    robot_code=$(prompt_input "机器人 RobotCode")

    cat >> "$CONFIG_FILE" << EOF

# 钉钉配置
DINGTALK_ENABLED=true
DINGTALK_APP_KEY='$app_key'
DINGTALK_APP_SECRET='$app_secret'
DINGTALK_ROBOT_CODE='$robot_code'
EOF

    CONFIGURED_CHANNELS+=("dingtalk")
    log_success "钉钉配置完成"
}

configure_channel_telegram() {
    echo -e "\n${BOLD}配置 Telegram${NC}\n"
    echo -e "${DIM}请通过 @BotFather 创建机器人${NC}\n"

    local bot_token

    bot_token=$(prompt_input "Bot Token" "" "true")
    if [[ -z "$bot_token" ]]; then
        log_warn "跳过 Telegram 配置"
        return 1
    fi

    cat >> "$CONFIG_FILE" << EOF

# Telegram 配置
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN='$bot_token'
EOF

    CONFIGURED_CHANNELS+=("telegram")
    log_success "Telegram 配置完成"
}

configure_channel_discord() {
    echo -e "\n${BOLD}配置 Discord${NC}\n"
    echo -e "${DIM}请前往 https://discord.com/developers 创建应用${NC}\n"

    local bot_token

    bot_token=$(prompt_input "Bot Token" "" "true")
    if [[ -z "$bot_token" ]]; then
        log_warn "跳过 Discord 配置"
        return 1
    fi

    cat >> "$CONFIG_FILE" << EOF

# Discord 配置
DISCORD_ENABLED=true
DISCORD_BOT_TOKEN='$bot_token'
EOF

    CONFIGURED_CHANNELS+=("discord")
    log_success "Discord 配置完成"
}

configure_channel_slack() {
    echo -e "\n${BOLD}配置 Slack${NC}\n"
    echo -e "${DIM}请前往 https://api.slack.com/apps 创建应用${NC}\n"

    local bot_token app_token signing_secret

    bot_token=$(prompt_input "Bot Token (xoxb-...)" "" "true")
    if [[ -z "$bot_token" ]]; then
        log_warn "跳过 Slack 配置"
        return 1
    fi

    app_token=$(prompt_input "App Token (xapp-...)" "" "true")
    signing_secret=$(prompt_input "Signing Secret" "" "true")

    cat >> "$CONFIG_FILE" << EOF

# Slack 配置
SLACK_ENABLED=true
SLACK_BOT_TOKEN='$bot_token'
SLACK_APP_TOKEN='$app_token'
SLACK_SIGNING_SECRET='$signing_secret'
EOF

    CONFIGURED_CHANNELS+=("slack")
    log_success "Slack 配置完成"
}

configure_channel() {
    local channel_name="$1"
    local channel_info="${CHANNELS[$channel_name]}"
    IFS='|' read -r channel_id description <<< "$channel_info"

    case "$channel_id" in
        feishu) configure_channel_feishu ;;
        wecom) configure_channel_wecom ;;
        dingtalk) configure_channel_dingtalk ;;
        telegram) configure_channel_telegram ;;
        discord) configure_channel_discord ;;
        slack) configure_channel_slack ;;
        *) log_warn "暂不支持 $channel_name" ;;
    esac
}

# ============== 系统安装 ==============
install_dependencies() {
    log_step "安装系统依赖"

    # 检测包管理器
    if command_exists apt-get; then
        PKG_MANAGER="apt"
    elif command_exists yum; then
        PKG_MANAGER="yum"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
    else
        log_error "不支持的系统，请手动安装 Node.js 22、nginx、git"
        exit 1
    fi

    # Node.js 22
    if ! command_exists node || [[ ! $(node --version 2>/dev/null) =~ ^v2[2-9] ]]; then
        log_info "安装 Node.js 22..."
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt-get install -y nodejs
        else
            curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
            sudo $PKG_MANAGER install -y nodejs
        fi
    fi
    log_success "Node.js $(node --version)"

    # pnpm
    if ! command_exists pnpm; then
        log_info "安装 pnpm..."
        sudo npm install -g pnpm
    fi
    log_success "pnpm $(pnpm --version)"

    # nginx
    if ! command_exists nginx; then
        log_info "安装 nginx..."
        sudo $PKG_MANAGER install -y nginx
    fi
    log_success "nginx 已安装"

    # git
    if ! command_exists git; then
        log_info "安装 git..."
        sudo $PKG_MANAGER install -y git
    fi
    log_success "git 已安装"
}

configure_nginx() {
    log_step "配置 Web 服务器"

    local server_ip="$1"

    sudo tee /etc/nginx/sites-available/moltbot > /dev/null 2>&1 || \
    sudo tee /etc/nginx/conf.d/moltbot.conf > /dev/null << EOF
server {
    listen 80;
    server_name _;

    # 飞书
    location /api/webhook/feishu {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT}/api/webhook/feishu;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    # 企业微信
    location /api/webhook/wecom {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT}/api/webhook/wecom;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    # 钉钉
    location /api/webhook/dingtalk {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT}/api/webhook/dingtalk;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    location / {
        return 200 'Moltbot Server OK';
        add_header Content-Type text/plain;
    }
}
EOF

    # Debian/Ubuntu
    if [[ -d /etc/nginx/sites-enabled ]]; then
        sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot
        sudo rm -f /etc/nginx/sites-enabled/default
    fi

    sudo nginx -t && sudo systemctl restart nginx
    log_success "nginx 配置完成"
}

install_moltbot() {
    log_step "安装 Moltbot"

    if [[ -d "$MOLTBOT_DIR/.git" ]]; then
        log_info "更新代码..."
        cd "$MOLTBOT_DIR"
        git pull
    else
        if [[ -d "$MOLTBOT_DIR" ]]; then
            log_warn "目录已存在，备份并重新克隆"
            mv "$MOLTBOT_DIR" "${MOLTBOT_DIR}.bak.$(date +%s)"
        fi
        log_info "克隆代码..."
        git clone "$MOLTBOT_REPO" "$MOLTBOT_DIR"
    fi

    cd "$MOLTBOT_DIR"

    log_info "安装依赖..."
    pnpm install

    log_info "构建项目..."
    pnpm build

    log_success "Moltbot 安装完成"
}

apply_configuration() {
    log_step "应用配置"

    cd "$MOLTBOT_DIR"

    # 基础配置
    pnpm moltbot config set gateway.mode local
    pnpm moltbot config set gateway.auth.token "$GATEWAY_TOKEN"

    # 读取配置文件并应用
    source "$CONFIG_FILE"

    # AI 提供商配置
    for provider in "${CONFIGURED_PROVIDERS[@]}"; do
        local api_key_var="PROVIDER_${provider^^}_API_KEY"
        local base_url_var="PROVIDER_${provider^^}_BASE_URL"
        local model_var="PROVIDER_${provider^^}_MODEL"

        local api_key="${!api_key_var}"
        local base_url="${!base_url_var}"
        local model="${!model_var}"

        if [[ -n "$api_key" ]]; then
            pnpm moltbot config set "providers.${provider}.apiKey" "$api_key"
            [[ -n "$base_url" ]] && pnpm moltbot config set "providers.${provider}.baseUrl" "$base_url"

            # 设置第一个配置的提供商为默认
            if [[ -z "$DEFAULT_MODEL_SET" ]]; then
                pnpm moltbot config set "models.default" "${provider}/${model}"
                DEFAULT_MODEL_SET=true
            fi
        fi
    done

    # 渠道配置
    for channel in "${CONFIGURED_CHANNELS[@]}"; do
        case "$channel" in
            feishu)
                pnpm moltbot config set channels.feishu.enabled true
                pnpm moltbot config set channels.feishu.appId "$FEISHU_APP_ID"
                pnpm moltbot config set channels.feishu.appSecret "$FEISHU_APP_SECRET"
                [[ -n "$FEISHU_VERIFICATION_TOKEN" ]] && \
                    pnpm moltbot config set channels.feishu.verificationToken "$FEISHU_VERIFICATION_TOKEN"
                [[ -n "$FEISHU_ENCRYPT_KEY" ]] && \
                    pnpm moltbot config set channels.feishu.encryptKey "$FEISHU_ENCRYPT_KEY"
                pnpm moltbot config set channels.feishu.webhookUrl "http://${SERVER_IP}/api/webhook/feishu"
                if [[ -n "$FEISHU_ALLOW_FROM" ]] && [[ "$FEISHU_ALLOW_FROM" != "*" ]]; then
                    local allow_json=$(echo "$FEISHU_ALLOW_FROM" | sed 's/ //g' | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
                    pnpm moltbot config set channels.feishu.allowFrom "$allow_json"
                    pnpm moltbot config set channels.feishu.dmPolicy "allowlist"
                elif [[ "$FEISHU_ALLOW_FROM" == "*" ]]; then
                    pnpm moltbot config set channels.feishu.dmPolicy "open"
                else
                    pnpm moltbot config set channels.feishu.dmPolicy "pairing"
                fi
                ;;
            wecom)
                pnpm moltbot config set channels.wecom.enabled true
                pnpm moltbot config set channels.wecom.corpId "$WECOM_CORP_ID"
                pnpm moltbot config set channels.wecom.agentId "$WECOM_AGENT_ID"
                pnpm moltbot config set channels.wecom.secret "$WECOM_SECRET"
                [[ -n "$WECOM_TOKEN" ]] && pnpm moltbot config set channels.wecom.token "$WECOM_TOKEN"
                [[ -n "$WECOM_ENCODING_AES_KEY" ]] && \
                    pnpm moltbot config set channels.wecom.encodingAesKey "$WECOM_ENCODING_AES_KEY"
                pnpm moltbot config set channels.wecom.webhookUrl "http://${SERVER_IP}/api/webhook/wecom"
                ;;
            telegram)
                pnpm moltbot config set channels.telegram.enabled true
                pnpm moltbot config set channels.telegram.botToken "$TELEGRAM_BOT_TOKEN"
                ;;
            discord)
                pnpm moltbot config set channels.discord.enabled true
                pnpm moltbot config set channels.discord.botToken "$DISCORD_BOT_TOKEN"
                ;;
            slack)
                pnpm moltbot config set channels.slack.enabled true
                pnpm moltbot config set channels.slack.botToken "$SLACK_BOT_TOKEN"
                [[ -n "$SLACK_APP_TOKEN" ]] && pnpm moltbot config set channels.slack.appToken "$SLACK_APP_TOKEN"
                [[ -n "$SLACK_SIGNING_SECRET" ]] && \
                    pnpm moltbot config set channels.slack.signingSecret "$SLACK_SIGNING_SECRET"
                ;;
        esac
    done

    log_success "配置应用完成"
}

setup_systemd() {
    log_step "配置系统服务"

    sudo tee /etc/systemd/system/moltbot.service > /dev/null << EOF
[Unit]
Description=Moltbot Gateway Service
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

    sleep 3

    if systemctl is-active --quiet moltbot; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败，请检查日志: journalctl -u moltbot -f"
    fi
}

print_summary() {
    local server_ip="$1"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    安装完成!                                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}服务器信息${NC}"
    echo -e "  地址:       http://${server_ip}"
    echo -e "  安装目录:   ${MOLTBOT_DIR}"
    echo -e "  Gateway:    http://127.0.0.1:${GATEWAY_PORT}"
    echo ""

    if [[ ${#CONFIGURED_CHANNELS[@]} -gt 0 ]]; then
        echo -e "${BOLD}Webhook 地址${NC}"
        for channel in "${CONFIGURED_CHANNELS[@]}"; do
            echo -e "  ${channel}:  http://${server_ip}/api/webhook/${channel}"
        done
        echo ""
    fi

    echo -e "${BOLD}常用命令${NC}"
    echo -e "  查看状态:   sudo systemctl status moltbot"
    echo -e "  查看日志:   sudo journalctl -u moltbot -f"
    echo -e "  重启服务:   sudo systemctl restart moltbot"
    echo -e "  修改配置:   cd $MOLTBOT_DIR && pnpm moltbot config set <key> <value>"
    echo ""
    echo -e "${DIM}配置文件: ~/.clawdbot/config.yaml${NC}"
    echo -e "${DIM}临时配置: ${CONFIG_FILE}${NC}"
    echo ""
}

# ============== 主流程 ==============
main() {
    clear
    print_logo

    # 检查非 root
    if [[ $EUID -eq 0 ]]; then
        log_error "请勿使用 root 用户运行"
        log_info "请使用普通用户运行，脚本会在需要时请求 sudo 权限"
        exit 1
    fi

    # 临时配置文件
    CONFIG_FILE=$(mktemp)
    CONFIGURED_PROVIDERS=()
    CONFIGURED_CHANNELS=()
    DEFAULT_MODEL_SET=""

    # 获取服务器 IP
    log_info "获取服务器信息..."
    SERVER_IP=$(get_public_ip)
    echo -e "  公网 IP: ${BOLD}${SERVER_IP}${NC}"

    SERVER_IP=$(prompt_input "确认服务器 IP" "$SERVER_IP")

    # 生成 Gateway Token
    GATEWAY_TOKEN="moltbot-$(openssl rand -hex 12)"

    # ===== 选择 AI 提供商 =====
    log_step "选择 AI 提供商"
    echo -e "${DIM}至少选择一个 AI 提供商来驱动聊天机器人${NC}"

    ai_options=()
    for key in "${!AI_PROVIDERS[@]}"; do
        ai_options+=("$key")
    done

    # 按推荐顺序排序
    sorted_ai=("DeepSeek" "Kimi (月之暗面)" "通义千问" "智谱 GLM" "OpenAI" "OpenAI 兼容")

    echo ""
    for i in "${!sorted_ai[@]}"; do
        provider="${sorted_ai[$i]}"
        info="${AI_PROVIDERS[$provider]}"
        IFS='|' read -r _ _ _ desc <<< "$info"
        echo -e "  $((i+1)). ${BOLD}$provider${NC} - ${DIM}$desc${NC}"
    done

    echo ""
    read -p "选择 AI 提供商 (多选用逗号分隔, 如 1,2): " ai_choices

    IFS=',' read -ra ai_nums <<< "$ai_choices"
    for num in "${ai_nums[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#sorted_ai[@]} )); then
            configure_ai_provider "${sorted_ai[$((num-1))]}"
        fi
    done

    if [[ ${#CONFIGURED_PROVIDERS[@]} -eq 0 ]]; then
        log_error "请至少配置一个 AI 提供商"
        exit 1
    fi

    # ===== 选择通讯渠道 =====
    log_step "选择通讯渠道"
    echo -e "${DIM}选择要接入的通讯平台${NC}"

    sorted_channels=("飞书 (Feishu)" "企业微信 (WeCom)" "钉钉 (DingTalk)" "Telegram" "Discord" "Slack")

    echo ""
    for i in "${!sorted_channels[@]}"; do
        channel="${sorted_channels[$i]}"
        info="${CHANNELS[$channel]}"
        IFS='|' read -r _ desc <<< "$info"
        echo -e "  $((i+1)). ${BOLD}$channel${NC} - ${DIM}$desc${NC}"
    done

    echo ""
    read -p "选择通讯渠道 (多选用逗号分隔, 如 1,2): " channel_choices

    IFS=',' read -ra channel_nums <<< "$channel_choices"
    for num in "${channel_nums[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#sorted_channels[@]} )); then
            configure_channel "${sorted_channels[$((num-1))]}"
        fi
    done

    if [[ ${#CONFIGURED_CHANNELS[@]} -eq 0 ]]; then
        log_warn "未配置任何通讯渠道，将只能通过 API 访问"
        if ! confirm "是否继续?"; then
            exit 0
        fi
    fi

    # ===== 确认安装 =====
    echo ""
    echo -e "${BOLD}配置摘要${NC}"
    echo -e "  AI 提供商: ${CONFIGURED_PROVIDERS[*]}"
    echo -e "  通讯渠道:  ${CONFIGURED_CHANNELS[*]}"
    echo -e "  服务器 IP: ${SERVER_IP}"
    echo -e "  安装目录:  ${MOLTBOT_DIR}"
    echo ""

    if ! confirm "确认开始安装?"; then
        log_info "安装已取消"
        exit 0
    fi

    # ===== 执行安装 =====
    install_dependencies
    configure_nginx "$SERVER_IP"
    install_moltbot
    apply_configuration
    setup_systemd

    # ===== 完成 =====
    print_summary "$SERVER_IP"

    # 清理临时文件
    rm -f "$CONFIG_FILE"
}

# 运行
main "$@"
