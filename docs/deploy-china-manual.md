# Moltbot 国内服务器手工部署指南

本文档介绍如何在国内 Linux 服务器上手工部署 Moltbot，支持 DeepSeek AI 和飞书渠道。

## 环境要求

- Ubuntu 22.04 / Debian 12 或更高版本
- 2GB+ 内存
- 开放端口：22 (SSH)、80 (HTTP)

## 第一步：安装系统依赖

### 1.1 安装 Node.js 22

```bash
# 添加 NodeSource 仓库并安装
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# 验证安装
node --version  # 应显示 v22.x.x
```

### 1.2 安装 pnpm

```bash
sudo npm install -g pnpm

# 验证安装
pnpm --version
```

### 1.3 安装 nginx

```bash
sudo apt-get install -y nginx

# 验证安装
nginx -v
```

## 第二步：配置 nginx 反向代理

创建 nginx 配置文件：

```bash
sudo tee /etc/nginx/sites-available/moltbot << 'EOF'
server {
    listen 80;
    server_name _;

    # 飞书 Webhook
    location /api/webhook/feishu {
        proxy_pass http://127.0.0.1:18789/api/webhook/feishu;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 企业微信 Webhook (可选)
    location /api/webhook/wecom {
        proxy_pass http://127.0.0.1:18789/api/webhook/wecom;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 默认响应
    location / {
        return 200 'Moltbot Server';
        add_header Content-Type text/plain;
    }
}
EOF
```

启用配置并重启 nginx：

```bash
# 启用站点配置
sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot

# 禁用默认站点
sudo rm -f /etc/nginx/sites-enabled/default

# 测试配置
sudo nginx -t

# 重启 nginx
sudo systemctl restart nginx

# 验证 nginx 运行
curl http://localhost/
# 应返回: Moltbot Server
```

## 第三步：获取 Moltbot 代码

### 方式一：从 GitHub 克隆

```bash
cd ~
git clone https://github.com/moltbot/moltbot.git
cd moltbot
```

### 方式二：从本地同步 (开发环境)

在本地机器执行：

```bash
rsync -avz --exclude='node_modules' --exclude='dist' --exclude='.git' \
    /path/to/moltbot/ ubuntu@<服务器IP>:~/moltbot/
```

## 第四步：安装依赖并构建

```bash
cd ~/moltbot

# 安装依赖
pnpm install

# 构建项目
pnpm build
```

> **注意**: 首次构建可能需要几分钟，请耐心等待。

## 第五步：配置 Moltbot

### 5.1 配置 Gateway

```bash
cd ~/moltbot

# 设置 gateway 模式
pnpm moltbot config set gateway.mode local

# 设置认证令牌 (用于 API 访问)
pnpm moltbot config set gateway.auth.token 'your-secure-token-here'
```

### 5.2 配置 DeepSeek AI

```bash
# 设置 DeepSeek API Key
pnpm moltbot config set providers.deepseek.apiKey 'sk-your-deepseek-api-key'

# 设置默认模型
pnpm moltbot config set models.default 'deepseek/deepseek-chat'

# 可选：使用 DeepSeek R1 推理模型
# pnpm moltbot config set models.default 'deepseek/deepseek-reasoner'
```

### 5.3 配置飞书渠道

```bash
# 启用飞书
pnpm moltbot config set channels.feishu.enabled true

# 设置应用凭据 (从飞书开放平台获取)
pnpm moltbot config set channels.feishu.appId 'cli_xxxxxxxx'
pnpm moltbot config set channels.feishu.appSecret 'your-app-secret'

# 设置事件订阅验证令牌
pnpm moltbot config set channels.feishu.verificationToken 'your-verification-token'

# 设置 Webhook URL (替换为你的服务器 IP)
pnpm moltbot config set channels.feishu.webhookUrl 'http://你的服务器IP/api/webhook/feishu'

# 设置允许的用户 (open_id 列表)
pnpm moltbot config set channels.feishu.allowFrom '["ou_xxxxx", "ou_yyyyy"]'

# 设置 DM 策略
pnpm moltbot config set channels.feishu.dmPolicy 'allowlist'

# 可选：设置消息加密密钥
# pnpm moltbot config set channels.feishu.encryptKey 'your-encrypt-key'

# 可选：自定义 "思考中" 提示消息
# pnpm moltbot config set channels.feishu.thinkingMessage '🤔 正在思考中，请稍候...'
# 设为空字符串可禁用：
# pnpm moltbot config set channels.feishu.thinkingMessage ''
```

### 5.4 查看配置

```bash
# 查看当前配置
pnpm moltbot config list

# 查看配置文件
cat ~/.clawdbot/config.yaml
```

## 第六步：启动 Gateway

### 前台运行 (调试用)

```bash
cd ~/moltbot
pnpm moltbot gateway run --bind 0.0.0.0 --port 18789 --force
```

### 后台运行 (生产环境)

```bash
cd ~/moltbot

# 停止已有进程
pkill -9 -f 'moltbot.*gateway' || true

# 后台启动
nohup pnpm moltbot gateway run --bind 0.0.0.0 --port 18789 --force > /tmp/moltbot-gateway.log 2>&1 &

# 验证启动
sleep 3
pgrep -f 'moltbot.*gateway' && echo "Gateway 启动成功" || echo "Gateway 启动失败"
```

### 使用 tmux (推荐)

```bash
# 创建 tmux 会话
tmux new-session -d -s moltbot

# 在 tmux 中启动 gateway
tmux send-keys -t moltbot 'cd ~/moltbot && pnpm moltbot gateway run --bind 0.0.0.0 --port 18789 --force' Enter

# 查看 tmux 会话
tmux attach -t moltbot

# 退出 tmux (不停止服务): Ctrl+B, D
```

### 使用 systemd (推荐用于生产)

创建 systemd 服务：

```bash
sudo tee /etc/systemd/system/moltbot.service << 'EOF'
[Unit]
Description=Moltbot Gateway
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/moltbot
ExecStart=/usr/bin/pnpm moltbot gateway run --bind 0.0.0.0 --port 18789 --force
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# 重载 systemd
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start moltbot

# 设置开机自启
sudo systemctl enable moltbot

# 查看状态
sudo systemctl status moltbot

# 查看日志
sudo journalctl -u moltbot -f
```

## 第七步：配置飞书开放平台

### 7.1 创建应用

1. 登录 [飞书开放平台](https://open.feishu.cn/)
2. 创建企业自建应用
3. 获取 App ID 和 App Secret

### 7.2 启用机器人能力

1. 进入应用 → 添加应用能力 → 机器人
2. 配置机器人名称和头像

### 7.3 配置事件订阅

1. 进入 事件订阅 页面
2. 设置请求地址：`http://你的服务器IP/api/webhook/feishu`
3. 点击验证 (服务器需已启动)
4. 获取 Verification Token
5. 添加事件：`im.message.receive_v1` (接收消息)

### 7.4 配置权限

进入 权限管理，开通以下权限：
- `im:message:send_as_bot` - 以应用身份发送消息
- `im:message` - 获取与发送单聊、群组消息
- `contact:user.id:readonly` - 获取用户 ID (可选)

### 7.5 发布应用

1. 进入 版本管理与发布
2. 创建版本并提交审核
3. 审核通过后发布

### 7.6 获取用户 open_id

在飞书中给机器人发消息，查看服务器日志获取你的 open_id：

```bash
tail -f /tmp/moltbot-gateway.log | grep open_id
```

## 常用命令

### 日志查看

```bash
# 查看实时日志
tail -f /tmp/moltbot-gateway.log

# 查看最近 100 行
tail -100 /tmp/moltbot-gateway.log

# 搜索错误
grep -i error /tmp/moltbot-gateway.log
```

### 服务管理

```bash
# 重启 gateway
pkill -9 -f 'moltbot.*gateway'
cd ~/moltbot && nohup pnpm moltbot gateway run --bind 0.0.0.0 --port 18789 --force > /tmp/moltbot-gateway.log 2>&1 &

# 检查端口
ss -ltnp | grep 18789

# 检查进程
pgrep -af moltbot
```

### 渠道状态

```bash
cd ~/moltbot

# 查看渠道状态
pnpm moltbot channels status

# 带探测的状态检查
pnpm moltbot channels status --probe
```

### 配置修改

```bash
cd ~/moltbot

# 查看配置
pnpm moltbot config list

# 修改配置
pnpm moltbot config set <key> <value>

# 直接编辑配置文件
nano ~/.clawdbot/config.yaml
```

## 故障排查

### 飞书收不到消息

1. 检查事件订阅是否配置正确
2. 检查 `im.message.receive_v1` 事件是否添加
3. 检查应用是否已发布
4. 检查权限是否已开通
5. 查看服务器日志是否收到请求

### Gateway 启动失败

```bash
# 查看详细错误
cat /tmp/moltbot-gateway.log

# 检查配置
pnpm moltbot config list

# 检查端口占用
ss -ltnp | grep 18789
```

### API 调用失败

```bash
# 测试 DeepSeek API
curl https://api.deepseek.com/v1/models \
  -H "Authorization: Bearer sk-your-api-key"

# 测试飞书 API (获取 token)
curl -X POST https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal \
  -H "Content-Type: application/json" \
  -d '{"app_id":"cli_xxx","app_secret":"xxx"}'
```

## 更新部署

```bash
cd ~/moltbot

# 拉取最新代码 (如果使用 git)
git pull

# 或从本地同步
# (在本地执行 rsync 命令)

# 重新安装依赖
pnpm install

# 重新构建
pnpm build

# 重启服务
pkill -9 -f 'moltbot.*gateway'
nohup pnpm moltbot gateway run --bind 0.0.0.0 --port 18789 --force > /tmp/moltbot-gateway.log 2>&1 &
```

## 配置示例

完整的 `~/.clawdbot/config.yaml` 示例：

```yaml
gateway:
  mode: local
  auth:
    token: your-secure-token

providers:
  deepseek:
    apiKey: sk-your-deepseek-api-key

models:
  default: deepseek/deepseek-chat

channels:
  feishu:
    enabled: true
    appId: cli_xxxxxxxx
    appSecret: your-app-secret
    verificationToken: your-verification-token
    webhookUrl: http://your-server-ip/api/webhook/feishu
    dmPolicy: allowlist
    allowFrom:
      - ou_xxxxx
      - ou_yyyyy
    thinkingMessage: "🤔 正在思考中，请稍候..."
```
