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

# 禁用交互式提示
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

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
NODE_MIN_VERSION=22

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

# 检查 Node.js 版本是否满足要求
check_node_version() {
    if ! command -v node &>/dev/null; then
        return 1
    fi
    local version=$(node -v | sed 's/v//' | cut -d. -f1)
    [[ $version -ge $NODE_MIN_VERSION ]]
}

# 带重试的命令执行
retry_cmd() {
    local max_attempts=3
    local attempt=1
    local delay=2

    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "命令失败，${delay}秒后重试 (${attempt}/${max_attempts})..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done

    log_err "命令执行失败: $*"
    return 1
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

if [[ $EUID -eq 0 ]]; then
    log_err "请使用普通用户运行 (非 root)"
    exit 1
fi

SERVER_IP=$(get_ip)
echo -e "服务器 IP: ${BOLD}${SERVER_IP}${NC}\n"

# ========== 检测系统环境 ==========
if ! $DRY_RUN; then
    echo -e "${BOLD}检测系统环境${NC}\n"

    # 检测包管理器
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        log_ok "包管理器: apt-get (Debian/Ubuntu)"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        log_ok "包管理器: yum (CentOS/RHEL)"
    else
        PKG_MANAGER="unknown"
        log_warn "未识别的包管理器"
    fi

    # 检测必需工具
    MISSING_DEPS=()

    if ! command -v curl &>/dev/null; then
        MISSING_DEPS+=("curl")
    else
        log_ok "curl 已安装"
    fi

    if ! command -v git &>/dev/null; then
        MISSING_DEPS+=("git")
    else
        log_ok "git 已安装: $(git --version | head -n1)"
    fi

    if ! check_node_version; then
        MISSING_DEPS+=("nodejs")
    else
        log_ok "Node.js 已安装: $(node -v)"
    fi

    if ! command -v npm &>/dev/null; then
        MISSING_DEPS+=("npm")
    else
        log_ok "npm 已安装: $(npm -v)"
    fi

    if ! command -v pnpm &>/dev/null; then
        MISSING_DEPS+=("pnpm")
    else
        log_ok "pnpm 已安装: $(pnpm -v)"
    fi

    if ! command -v nginx &>/dev/null; then
        MISSING_DEPS+=("nginx")
    else
        log_ok "nginx 已安装: $(nginx -v 2>&1 | head -n1)"
    fi

    echo ""
fi

# ========== 检测安装状态 ==========
NEED_CLONE=true
NEED_BUILD=true
IS_GIT_REPO=false

if [[ -d "$MOLTBOT_DIR" ]]; then
    # 检查是否是有效的 Moltbot 项目目录
    if [[ -f "$MOLTBOT_DIR/package.json" ]]; then
        echo -e "${GREEN}检测到 Moltbot 项目目录${NC} ($MOLTBOT_DIR)"
        NEED_CLONE=false

        # 检查是否是 Git 仓库
        if [[ -d "$MOLTBOT_DIR/.git" ]]; then
            IS_GIT_REPO=true
            log_ok "Git 仓库 (可通过 git pull 更新)"
        else
            log_ok "非 Git 部署 (rsync/手动上传)"
        fi

        # 检查是否已构建（包括 UI）
        if [[ -d "$MOLTBOT_DIR/node_modules" ]] && [[ -d "$MOLTBOT_DIR/dist" ]] && [[ -d "$MOLTBOT_DIR/dist/control-ui" ]]; then
            echo -e "${GREEN}检测到已构建的项目（包括 UI）${NC}\n"
            NEED_BUILD=false
        else
            echo -e "${YELLOW}项目未构建或构建不完整${NC}\n"
            if [[ ! -d "$MOLTBOT_DIR/dist/control-ui" ]]; then
                log_warn "UI 未构建"
            fi
        fi
    else
        echo -e "${YELLOW}目录 $MOLTBOT_DIR 存在但不包含 package.json${NC}\n"
        log_warn "该目录似乎不是有效的 Moltbot 项目"
        read -rp "是否删除该目录并重新安装? [y/N]: " remove_dir
        if [[ "$remove_dir" =~ ^[Yy]$ ]]; then
            rm -rf "$MOLTBOT_DIR"
            log_ok "目录已删除，将重新克隆代码"
        else
            log_err "安装已取消"
            exit 1
        fi
    fi
else
    echo -e "${BLUE}准备全新安装${NC}\n"
fi

# ========== 安装系统依赖 ==========
if ! $DRY_RUN && [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo -e "${BOLD}[1/5] 安装系统依赖${NC}\n"
    log_info "缺少以下依赖: ${MISSING_DEPS[*]}"

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_info "更新 apt 缓存..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq

        # 安装基础工具
        if [[ " ${MISSING_DEPS[*]} " =~ " curl " ]]; then
            log_info "安装 curl..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q curl
        fi

        if [[ " ${MISSING_DEPS[*]} " =~ " git " ]]; then
            log_info "安装 git..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q git
        fi

        # 安装 Node.js
        if [[ " ${MISSING_DEPS[*]} " =~ " nodejs " ]]; then
            log_info "安装 Node.js ${NODE_MIN_VERSION}..."
            retry_cmd curl -fsSL https://deb.nodesource.com/setup_${NODE_MIN_VERSION}.x | sudo -E bash -
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q nodejs

            if ! check_node_version; then
                log_err "Node.js 安装失败或版本不满足要求 (需要 v${NODE_MIN_VERSION}+)"
                exit 1
            fi
            log_ok "Node.js $(node -v) 安装成功"
        fi

        # 安装 pnpm
        if [[ " ${MISSING_DEPS[*]} " =~ " pnpm " ]]; then
            log_info "安装 pnpm..."
            retry_cmd sudo npm install -g pnpm

            if ! command -v pnpm &>/dev/null; then
                log_err "pnpm 安装失败"
                exit 1
            fi
            log_ok "pnpm $(pnpm -v) 安装成功"
        fi

        # 安装 nginx
        if [[ " ${MISSING_DEPS[*]} " =~ " nginx " ]]; then
            log_info "安装 nginx..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx
            log_ok "nginx 安装成功"
        fi

    elif [[ "$PKG_MANAGER" == "yum" ]]; then
        # 安装基础工具
        if [[ " ${MISSING_DEPS[*]} " =~ " curl " ]]; then
            log_info "安装 curl..."
            sudo yum install -y curl
        fi

        if [[ " ${MISSING_DEPS[*]} " =~ " git " ]]; then
            log_info "安装 git..."
            sudo yum install -y git
        fi

        # 安装 Node.js
        if [[ " ${MISSING_DEPS[*]} " =~ " nodejs " ]]; then
            log_info "安装 Node.js ${NODE_MIN_VERSION}..."
            retry_cmd curl -fsSL https://rpm.nodesource.com/setup_${NODE_MIN_VERSION}.x | sudo bash -
            sudo yum install -y nodejs

            if ! check_node_version; then
                log_err "Node.js 安装失败或版本不满足要求 (需要 v${NODE_MIN_VERSION}+)"
                exit 1
            fi
            log_ok "Node.js $(node -v) 安装成功"
        fi

        # 安装 pnpm
        if [[ " ${MISSING_DEPS[*]} " =~ " pnpm " ]]; then
            log_info "安装 pnpm..."
            retry_cmd sudo npm install -g pnpm

            if ! command -v pnpm &>/dev/null; then
                log_err "pnpm 安装失败"
                exit 1
            fi
            log_ok "pnpm $(pnpm -v) 安装成功"
        fi

        # 安装 nginx
        if [[ " ${MISSING_DEPS[*]} " =~ " nginx " ]]; then
            log_info "安装 nginx..."
            sudo yum install -y nginx
            log_ok "nginx 安装成功"
        fi

    else
        log_err "无法自动安装依赖，请手动安装: ${MISSING_DEPS[*]}"
        exit 1
    fi

    log_ok "系统依赖就绪\n"
elif ! $DRY_RUN; then
    echo -e "${BOLD}[1/5] 系统依赖${NC}\n"
    log_ok "所有依赖已满足\n"
else
    echo -e "${DIM}[dry-run] 跳过依赖安装${NC}\n"
fi

# ========== 获取代码 ==========
if $NEED_CLONE && ! $DRY_RUN; then
    echo -e "${BOLD}[2/5] 获取代码${NC}\n"
    log_info "克隆仓库到 $MOLTBOT_DIR..."

    # 优先尝试 GitHub，失败则使用 Gitee
    if ! git clone "$GITHUB_REPO" "$MOLTBOT_DIR" 2>/dev/null; then
        log_warn "GitHub 克隆失败，尝试 Gitee 镜像..."
        if ! git clone "$GITEE_REPO" "$MOLTBOT_DIR"; then
            log_err "代码克隆失败"
            exit 1
        fi
    fi

    IS_GIT_REPO=true
    log_ok "代码获取完成\n"
elif ! $DRY_RUN; then
    echo -e "${BOLD}[2/5] 代码仓库${NC}\n"
    log_ok "代码已存在，跳过克隆"

    # 如果是 Git 仓库，尝试更新代码
    if [[ "$IS_GIT_REPO" == true ]]; then
        cd "$MOLTBOT_DIR"
        log_info "检查更新..."
        git fetch origin --quiet 2>/dev/null || true
        LOCAL=$(git rev-parse @ 2>/dev/null)
        REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "$LOCAL")

        if [[ "$LOCAL" != "$REMOTE" ]]; then
            log_warn "发现新版本"
            read -rp "是否更新到最新版本? [y/N]: " update_code
            if [[ "$update_code" =~ ^[Yy]$ ]]; then
                git pull
                log_ok "代码已更新"
                NEED_BUILD=true  # 更新后需要重新构建
            fi
        else
            log_ok "代码已是最新"
        fi
    else
        log_info "非 Git 仓库，如需更新请使用 rsync 或其他方式同步代码"
    fi
    echo ""
else
    echo -e "${DIM}[dry-run] 跳过代码克隆${NC}\n"
fi

# ========== 构建项目 ==========
if ! $DRY_RUN; then
    cd "$MOLTBOT_DIR" || exit 1
else
    echo -e "${DIM}[dry-run] cd $MOLTBOT_DIR${NC}"
fi

if $NEED_BUILD && ! $DRY_RUN; then
    echo -e "${BOLD}[3/5] 构建项目${NC}\n"

    log_info "安装 npm 依赖..."
    if ! pnpm install; then
        log_err "依赖安装失败"
        exit 1
    fi
    log_ok "依赖安装完成"

    log_info "构建主程序..."
    if ! pnpm build; then
        log_err "主程序构建失败"
        exit 1
    fi
    log_ok "主程序构建完成"

    log_info "构建管理后台 UI..."
    if ! pnpm ui:build; then
        log_err "UI 构建失败"
        exit 1
    fi
    log_ok "UI 构建完成"

    log_ok "项目构建完成\n"
elif ! $DRY_RUN; then
    echo -e "${BOLD}[3/5] 项目构建${NC}\n"
    log_ok "项目已构建，跳过\n"
else
    echo -e "${DIM}[dry-run] 跳过构建${NC}\n"
fi

# ========== 配置 nginx ==========
echo -e "${BOLD}[4/5] 配置 Web 服务${NC}\n"

NGINX_CONF='# WebSocket upgrade map
map $http_upgrade $connection_upgrade {
    default upgrade;
    '\'''\'' close;
}

server {
    listen 80;
    server_name _;

    # 根路径 - WebSocket + UI
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;

        # WebSocket 支持
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # 标准代理头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket 超时
        proxy_read_timeout 86400;
    }

    # Webhook (企业微信等，飞书已改用长连接)
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
}'

if ! $DRY_RUN; then
    NGINX_CONFIGURED=false

    if [[ -d /etc/nginx/sites-available ]]; then
        # Debian/Ubuntu
        if [[ -f /etc/nginx/sites-available/moltbot ]]; then
            log_ok "nginx 配置已存在"
            NGINX_CONFIGURED=true
        else
            log_info "创建 nginx 配置..."
            echo "$NGINX_CONF" | sudo tee /etc/nginx/sites-available/moltbot >/dev/null
            sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot
            sudo rm -f /etc/nginx/sites-enabled/default

            log_info "测试 nginx 配置..."
            if sudo nginx -t 2>&1 | grep -q "successful"; then
                log_ok "nginx 配置有效"
                sudo systemctl enable nginx >/dev/null 2>&1
                sudo systemctl restart nginx

                if systemctl is-active --quiet nginx; then
                    log_ok "nginx 启动成功"
                    NGINX_CONFIGURED=true
                else
                    log_err "nginx 启动失败"
                fi
            else
                log_err "nginx 配置测试失败"
                sudo nginx -t
            fi
        fi
    elif [[ -d /etc/nginx/conf.d ]]; then
        # CentOS/RHEL
        if [[ -f /etc/nginx/conf.d/moltbot.conf ]]; then
            log_ok "nginx 配置已存在"
            NGINX_CONFIGURED=true
        else
            log_info "创建 nginx 配置..."
            echo "$NGINX_CONF" | sudo tee /etc/nginx/conf.d/moltbot.conf >/dev/null

            log_info "测试 nginx 配置..."
            if sudo nginx -t 2>&1 | grep -q "successful"; then
                log_ok "nginx 配置有效"
                sudo systemctl enable nginx >/dev/null 2>&1
                sudo systemctl restart nginx

                if systemctl is-active --quiet nginx; then
                    log_ok "nginx 启动成功"
                    NGINX_CONFIGURED=true
                else
                    log_err "nginx 启动失败"
                fi
            else
                log_err "nginx 配置测试失败"
                sudo nginx -t
            fi
        fi
    else
        log_warn "未找到 nginx 配置目录"
    fi

    # 检查防火墙 (Ubuntu/Debian)
    if command -v ufw &>/dev/null; then
        if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
            if ! sudo ufw status | grep -q "80/tcp"; then
                log_warn "检测到 UFW 防火墙已启用但端口 80 未开放"
                read -rp "是否开放端口 80? [y/N]: " open_port
                if [[ "$open_port" =~ ^[Yy]$ ]]; then
                    sudo ufw allow 80/tcp
                    log_ok "端口 80 已开放"
                fi
            fi
        fi
    fi

    # 检查防火墙 (CentOS/RHEL)
    if command -v firewall-cmd &>/dev/null; then
        if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
            if ! sudo firewall-cmd --list-ports | grep -q "80/tcp"; then
                log_warn "检测到 firewalld 已启用但端口 80 未开放"
                read -rp "是否开放端口 80? [y/N]: " open_port
                if [[ "$open_port" =~ ^[Yy]$ ]]; then
                    sudo firewall-cmd --permanent --add-port=80/tcp
                    sudo firewall-cmd --reload
                    log_ok "端口 80 已开放"
                fi
            fi
        fi
    fi

    if $NGINX_CONFIGURED; then
        log_ok "Web 服务配置完成\n"
    else
        log_warn "Web 服务配置可能未完成，请手动检查\n"
    fi
else
    echo -e "${DIM}[dry-run] 跳过 nginx 配置${NC}\n"
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
cfg gateway.controlUi.basePath "/ui"
cfg gateway.controlUi.allowInsecureAuth true
cfg gateway.controlUi.dangerouslyDisableDeviceAuth true
cfg gateway.trustedProxies '["127.0.0.1", "::1"]'
log_ok "Gateway 配置完成"

# ===== AI 提供商 =====
# 检查是否已配置 AI 提供商
HAS_AI_CONFIG=false
CONFIG_FILE="$HOME/.moltbot/config.json5"

if [[ -f "$CONFIG_FILE" ]]; then
    # 检查是否已配置环境变量中的 API Key
    if grep -q "DEEPSEEK_API_KEY\|MOONSHOT_API_KEY" "$CONFIG_FILE" 2>/dev/null; then
        HAS_AI_CONFIG=true
    fi
    # 或检查是否已配置默认模型
    if grep -q "agents.*defaults.*model.*primary" "$CONFIG_FILE" 2>/dev/null; then
        HAS_AI_CONFIG=true
    fi
fi

if $HAS_AI_CONFIG; then
    echo ""
    log_ok "检测到已配置的 AI 提供商"
    read -rp "是否重新配置? [y/N]: " reconfig
    if [[ ! "$reconfig" =~ ^[Yy]$ ]]; then
        log_info "跳过 AI 提供商配置"
        echo ""
    else
        HAS_AI_CONFIG=false
    fi
fi

if ! $HAS_AI_CONFIG; then
    echo ""
    echo -e "${BOLD}选择 AI 提供商:${NC}"
    echo "  1) DeepSeek     - 国产大模型，推荐"
    echo "  2) Kimi         - 月之暗面，长文本"
    echo ""
    read -rp "请选择 [1-2，可多选如 1,2]: " ai_choice

    IFS=',' read -ra ai_nums <<< "$ai_choice"
    first_model=""

    for n in "${ai_nums[@]}"; do
        n=$(echo "$n" | tr -d ' ')
        case "$n" in
        1)
            echo ""
            echo -e "${CYAN}配置 DeepSeek${NC} (https://platform.deepseek.com)"
            read -rp "API Key: " key
            if [[ -n "$key" ]]; then
                # 添加到环境变量配置
                cfg env.DEEPSEEK_API_KEY "$key"
                [[ -z "$first_model" ]] && first_model="deepseek/deepseek-chat"
                log_ok "DeepSeek 已配置 (通过环境变量)"
            fi
            ;;
        2)
            echo ""
            echo -e "${CYAN}配置 Kimi${NC} (https://platform.moonshot.cn)"
            read -rp "API Key: " key
            if [[ -n "$key" ]]; then
                # 添加到环境变量配置
                cfg env.MOONSHOT_API_KEY "$key"
                [[ -z "$first_model" ]] && first_model="moonshot/kimi-k2.5"
                # kimi-k2.5 要求 temperature=1
                cfg 'agents.defaults.models["moonshot/kimi-k2.5"].params.temperature' 1
                log_ok "Kimi 已配置 (通过环境变量)"
            fi
            ;;
        esac
    done

    [[ -n "$first_model" ]] && cfg agents.defaults.model.primary "$first_model"
fi

# ===== 通讯渠道 =====
echo ""
echo -e "${BOLD}选择通讯渠道:${NC}"
echo "  1) 飞书        - 字节跳动"
echo "  2) 企业微信    - 腾讯"
echo "  0) 跳过"
echo ""
read -rp "请选择 [0-2，可多选如 1,2]: " ch_choice

IFS=',' read -ra ch_nums <<< "$ch_choice"

for n in "${ch_nums[@]}"; do
    n=$(echo "$n" | tr -d ' ')
    case "$n" in
        1) # 飞书
            echo ""
            echo -e "${CYAN}配置飞书${NC} (https://open.feishu.cn)"
            read -rp "App ID: " app_id
            [[ -z "$app_id" ]] && continue
            read -rp "App Secret: " app_secret
            read -rp "允许的 open_id (逗号分隔，留空=配对模式): " allow

            log_info "安装飞书插件..."
            if ! $DRY_RUN; then
                pnpm moltbot plugins install @m1heng-clawd/feishu 2>/dev/null || log_warn "插件可能已安装"
            fi

            log_info "保存飞书配置 (WebSocket 长连接模式)..."
            cfg channels.feishu.enabled true
            cfg channels.feishu.appId "$app_id"
            cfg channels.feishu.appSecret "$app_secret"
            cfg channels.feishu.domain "feishu"
            cfg channels.feishu.connectionMode "websocket"
            cfg channels.feishu.requireMention true
            cfg channels.feishu.mediaMaxMb 30
            cfg channels.feishu.renderMode "auto"

            if [[ -n "$allow" ]]; then
                allow_json=$(echo "$allow" | sed 's/ //g;s/,/","/g;s/^/["/;s/$/"]/')
                cfg channels.feishu.allowFrom "$allow_json"
                cfg channels.feishu.dmPolicy allowlist
                cfg channels.feishu.groupPolicy allowlist
            else
                cfg channels.feishu.dmPolicy pairing
                cfg channels.feishu.groupPolicy allowlist
            fi
            log_ok "飞书已配置 (使用长连接模式，无需公网 IP)"
            echo -e "${YELLOW}重要: 在飞书开放平台选择【长连接】模式并订阅 im.message.receive_v1 事件${NC}"
            ;;
        2) # 企业微信
            echo ""
            echo -e "${CYAN}配置企业微信${NC} (https://work.weixin.qq.com)"
            read -rp "企业 ID (CorpID): " corp_id
            [[ -z "$corp_id" ]] && continue
            read -rp "应用 AgentId: " agent_id
            read -rp "应用 Secret: " secret
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
    esac
done

# ========== 创建 auth-profiles.json ==========
if ! $DRY_RUN; then
    echo ""
    log_info "创建认证配置文件（避免 API key 间歇性失败）..."

    AGENT_DIR="$HOME/.moltbot/agents/main/agent"
    mkdir -p "$AGENT_DIR"
    AUTH_PROFILES="$AGENT_DIR/auth-profiles.json"

    # 构建 JSON
    echo "{" > "$AUTH_PROFILES"
    FIRST=true

    # DeepSeek
    DEEPSEEK_KEY=$(pnpm moltbot config get env.DEEPSEEK_API_KEY 2>/dev/null | grep -v "^>" | grep -v "Config warnings" | tail -1 | tr -d '"' | xargs || echo "")
    if [[ -n "$DEEPSEEK_KEY" ]]; then
        [[ "$FIRST" == false ]] && echo "," >> "$AUTH_PROFILES"
        echo "  \"deepseek\": { \"apiKey\": \"$DEEPSEEK_KEY\" }" >> "$AUTH_PROFILES"
        FIRST=false
    fi

    # Moonshot
    MOONSHOT_KEY=$(pnpm moltbot config get env.MOONSHOT_API_KEY 2>/dev/null | grep -v "^>" | grep -v "Config warnings" | tail -1 | tr -d '"' | xargs || echo "")
    if [[ -n "$MOONSHOT_KEY" ]]; then
        [[ "$FIRST" == false ]] && echo "," >> "$AUTH_PROFILES"
        echo "  \"moonshot\": { \"apiKey\": \"$MOONSHOT_KEY\" }" >> "$AUTH_PROFILES"
        FIRST=false
    fi

    echo "}" >> "$AUTH_PROFILES"
    chmod 600 "$AUTH_PROFILES"
    log_ok "认证配置文件已创建: $AUTH_PROFILES\n"
else
    echo -e "${DIM}[dry-run] 跳过认证配置文件创建${NC}\n"
fi

# ========== 配置并启动系统服务 ==========
if ! $DRY_RUN; then
    log_info "配置系统服务..."

    # 确保 pnpm 路径
    PNPM_PATH=$(which pnpm)
    if [[ -z "$PNPM_PATH" ]]; then
        log_err "找不到 pnpm，请确保 pnpm 已安装"
        exit 1
    fi

    sudo tee /etc/systemd/system/moltbot.service >/dev/null << SVC
[Unit]
Description=Moltbot Gateway
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MOLTBOT_DIR
ExecStart=$PNPM_PATH moltbot gateway run --bind 0.0.0.0 --port ${GATEWAY_PORT} --force
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

    log_ok "systemd 服务配置完成"

    log_info "重载 systemd 配置..."
    sudo systemctl daemon-reload

    log_info "启用服务开机自启..."
    sudo systemctl enable moltbot >/dev/null 2>&1

    log_info "启动 Moltbot 服务..."
    sudo systemctl restart moltbot

    # 等待服务启动
    sleep 3

    # 检查服务状态
    if systemctl is-active --quiet moltbot; then
        log_ok "Moltbot 服务启动成功\n"
    else
        log_err "Moltbot 服务启动失败"
        echo ""
        log_warn "查看错误日志:"
        echo -e "${DIM}sudo journalctl -u moltbot -n 50 --no-pager${NC}"
        echo ""
        exit 1
    fi
else
    echo -e "${DIM}[dry-run] 跳过 systemd 服务配置${NC}\n"
fi

# ========== 安装完成 ==========
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    安装完成！                          ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}管理后台访问地址:${NC}"
echo -e "  ${CYAN}http://${SERVER_IP}/ui/?token=${GATEWAY_TOKEN}${NC}"
echo ""
echo -e "${DIM}首次访问请使用上面的完整 URL（包含 token 参数）${NC}"
echo -e "${DIM}浏览器会自动保存 token，以后可直接访问 http://${SERVER_IP}/ui/${NC}"
echo ""
echo -e "${BOLD}接入说明:${NC}"
echo "  飞书:     使用长连接模式，在飞书开放平台选择【长连接】并订阅 im.message.receive_v1"
echo "  企业微信: Webhook - http://${SERVER_IP}/api/webhook/wecom"
echo ""
echo -e "${BOLD}管理命令:${NC}"
echo "  sudo systemctl status moltbot       # 查看状态"
echo "  sudo systemctl stop moltbot         # 停止服务"
echo "  sudo systemctl start moltbot        # 启动服务"
echo "  sudo systemctl restart moltbot      # 重启服务"
echo "  sudo journalctl -u moltbot -f       # 查看实时日志"
echo "  sudo journalctl -u moltbot -n 100   # 查看最近 100 行日志"
echo ""
echo -e "${BOLD}重新配置:${NC}"
echo "  cd $MOLTBOT_DIR"
echo "  bash scripts/install.sh"
echo ""

if ! $DRY_RUN; then
    # 最终状态检查
    SERVICE_STATUS="未知"
    if systemctl is-active --quiet moltbot; then
        SERVICE_STATUS="${GREEN}运行中${NC}"
    else
        SERVICE_STATUS="${RED}已停止${NC}"
    fi

    NGINX_STATUS="未知"
    if systemctl is-active --quiet nginx; then
        NGINX_STATUS="${GREEN}运行中${NC}"
    else
        NGINX_STATUS="${RED}已停止${NC}"
    fi

    echo -e "${BOLD}服务状态:${NC}"
    echo -e "  Moltbot: $SERVICE_STATUS"
    echo -e "  Nginx:   $NGINX_STATUS"
    echo ""

    if systemctl is-active --quiet moltbot && systemctl is-active --quiet nginx; then
        log_ok "所有服务正常运行"
        echo ""
        echo -e "${CYAN}提示:${NC} 在浏览器访问 ${BOLD}http://${SERVER_IP}/ui/${NC} 开始使用"
    else
        log_warn "部分服务未运行，请检查日志"
    fi
else
    log_ok "[dry-run] 测试完成"
fi
