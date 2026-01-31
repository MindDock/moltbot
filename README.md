# Kimi 2.5 + 飞书一键部署腾讯云国内服务器版 Clawdbot

> 在腾讯云服务器（国内版，超便宜）上部署 Clawdbot，通过飞书与 Kimi 2.5 大模型（超便宜）对话。支持长连接模式，无需公网 IP 或域名。

## 📋 目录

- [前置准备](#前置准备)
  - [云服务器要求](#云服务器要求)
  - [飞书应用配置](#飞书应用配置)
  - [Kimi API Key](#kimi-api-key)
- [快速开始](#快速开始)
- [详细步骤](#详细步骤)
  - [1. 准备云服务器](#1-准备云服务器)
  - [2. 配置飞书应用](#2-配置飞书应用)
  - [3. 获取 Kimi API Key](#3-获取-kimi-api-key)
  - [4. 一键安装部署](#4-一键安装部署)
  - [5. 验证部署](#5-验证部署)
- [使用说明](#使用说明)
- [常见问题](#常见问题)
- [更新维护](#更新维护)

---

## 前置准备

### 云服务器要求

推荐ubuntu 22

| 配置项 | 最低要求 | 推荐配置 |
|--------|---------|---------|
| **CPU** | 2 核 | 4 核 |
| **内存** | 2 GB | 4 GB |
| **硬盘** | 20 GB | 40 GB |
| **操作系统** | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| **网络** | 1 Mbps | 5 Mbps |
| **端口** | 80 (HTTP) | 80 (HTTP) |

> **腾讯云推荐机型**:
> - 标准型 S5.MEDIUM4 (2核4G)
> - 地域: 北京/上海/广州（就近选择）
> - 系统盘: 50GB SSD云硬盘

### 飞书应用配置

需要准备以下信息：

- ✅ **App ID**: 应用凭证（格式: `cli_xxxxxxxxxxxx`）
- ✅ **App Secret**: 应用密钥
- ✅ **权限配置**:
  - 获取与发送单聊、群组消息
  - 读取用户发送的消息
  - 以应用的身份发送消息

### Kimi API Key

- ✅ 注册地址: https://platform.moonshot.cn
- ✅ API Key 格式: `sk-xxxxxxxxxxxxxxxxxxxxxxxxxx`
- ✅ 余额充值: 建议充值 20-50 元（按量付费）

---

## 快速开始

```bash
# 1. 克隆代码（或直接在服务器上执行下面的一键安装）
git clone https://github.com/MindDock/moltbot.git
cd moltbot
# 或者先git clone到本地，通过rsync传到服务器 
rsync -avz --progress ～/moltbot/ ubuntu@[服务器外网ip]:~/moltbot/ --exclude node_modules --exclude .git

# 2. 一键安装
ssh ~到主机
cd ~/moltbot/
bash scripts/install.sh
```

**仅需 5-10 分钟即可完成部署！**

---

## 详细步骤

### 1. 准备云服务器

#### 1.1 购买腾讯云服务器

1. 访问 [腾讯云控制台](https://console.cloud.tencent.com/cvm)
2. 点击「新建」创建云服务器
3. 配置选择：
   - **地域**: 北京/上海/广州（就近选择）
   - **实例**: 标准型 S5.MEDIUM4 (2核4G)
   - **镜像**: Ubuntu Server 22.04 LTS 64位
   - **系统盘**: 50GB SSD云硬盘
   - **公网IP**: 分配（带宽 1-5 Mbps）
   - **安全组**: 放行 80 端口（HTTP）

4. 设置服务器密码（或使用 SSH 密钥）
5. 购买并启动

#### 1.2 登录服务器

```bash
# 方式 1: 使用腾讯云网页终端（推荐新手）
在控制台点击「登录」按钮

# 方式 2: 使用本地 SSH 客户端
ssh ubuntu@你的服务器IP
```

#### 1.3 防火墙配置

确保安全组规则已放行：

| 协议 | 端口 | 来源 | 说明 |
|------|------|------|------|
| TCP | 22 | 0.0.0.0/0 | SSH 登录 |
| TCP | 80 | 0.0.0.0/0 | Web 访问 |

> 在腾讯云控制台 → 实例详情 → 安全组 → 添加规则

---

### 2. 配置飞书应用

#### 2.1 创建飞书应用

1. 访问 [飞书开放平台](https://open.feishu.cn)
2. 登录后，点击「创建应用」→「企业自建应用」
3. 填写应用信息：
   - 应用名称: `Kimi 智能助手`（可自定义）
   - 应用描述: `基于 Kimi 2.5 的 AI 对话助手`
   - 应用图标: 上传一个图标（可选）

#### 2.2 获取应用凭证

1. 进入应用管理页面
2. 点击「凭证与基础信息」
3. 记录以下信息：
   ```
   App ID: cli_xxxxxxxxxxxx
   App Secret: xxxxxxxxxxxxxxxxxxxxxxxx
   ```

#### 2.3 配置应用权限

1. 点击「权限管理」
2. 搜索并开通以下权限：

#### Required Permissions

| Permission | Scope | Description |
|------------|-------|-------------|
| `contact:user.base:readonly` | User info | Get basic user info (required to resolve sender display names for speaker attribution) |
| `im:message` | Messaging | Send and receive messages |
| `im:message.p2p_msg:readonly` | DM | Read direct messages to bot |
| `im:message.group_at_msg:readonly` | Group | Receive @mention messages in groups |
| `im:message:send_as_bot` | Send | Send messages as the bot |
| `im:resource` | Media | Upload and download images/files |

#### Optional Permissions

| Permission | Scope | Description |
|------------|-------|-------------|
| `im:message.group_msg` | Group | Read all group messages (sensitive) |
| `im:message:readonly` | Read | Get message history |
| `im:message:update` | Edit | Update/edit sent messages |
| `im:message:recall` | Recall | Recall sent messages |
| `im:message.reactions:read` | Reactions | View message reactions |

3. 点击「发布版本」→ 发布应用


#### 2.4 配置事件订阅（重要！）

1. 进入「事件订阅」页面
2. **选择长连接模式**（不是 HTTP 回调）

   > ⚠️ **关键步骤**: 必须选择「长连接」，否则无法接收消息！

3. 订阅事件：

| Event | Description |
|-------|-------------|
| `im.message.receive_v1` | Receive messages (required) |
| `im.message.message_read_v1` | Message read receipts |
| `im.chat.member.bot.added_v1` | Bot added to group |
| `im.chat.member.bot.deleted_v1` | Bot removed from group |

4. 保存配置

---

### 3. 获取 Kimi API Key

#### 3.1 注册 Kimi 账号

1. 访问 https://platform.moonshot.cn
2. 注册账号并登录
3. 完成实名认证（根据提示操作）

#### 3.2 创建 API Key

1. 进入「API 密钥管理」
2. 点击「创建新密钥」
3. 记录 API Key（格式: `sk-xxxxxx`）

   > ⚠️ **注意**: API Key 只显示一次，请妥善保存！

#### 3.3 充值余额

1. 进入「账户管理」→「充值」
2. 建议充值 20-50 元
3. 计费说明：
   - Kimi k2.5 模型约 ¥0.003/1000 tokens
   - 普通对话约 ¥0.01-0.05/次

---

### 4. 一键安装部署

#### 4.1 克隆代码

在服务器上执行：

```bash
# 方式 1: 从 GitHub 克隆（国外服务器）
git clone https://github.com/MindDock/moltbot.git

# 方式 2: 从 Gitee 克隆（国内服务器，推荐）
git clone https://gitee.com/minddock/moltbot.git

# 进入项目目录
cd moltbot
```

#### 4.2 运行安装脚本

```bash
bash scripts/install.sh
```

#### 4.3 交互式配置

脚本会自动检测环境并安装依赖，然后提示你配置：

**步骤 1: 选择 AI 提供商**

```
选择 AI 提供商:
  1) DeepSeek     - 国产大模型，推荐
  2) Kimi         - 月之暗面，长文本

请选择 [1-2，可多选如 1,2]: 2  ← 输入 2 并回车
```

**步骤 2: 输入 Kimi API Key**

```
配置 Kimi (https://platform.moonshot.cn)
API Key: sk-xxxxxxxxxxxxxxxxxxxxxx  ← 粘贴你的 API Key
```

**步骤 3: 选择通讯渠道**

```
选择通讯渠道:
  1) 飞书        - 字节跳动
  2) 企业微信    - 腾讯
  0) 跳过

请选择 [0-2，可多选如 1,2]: 1  ← 输入 1 并回车
```

**步骤 4: 输入飞书配置**

```
配置飞书 (https://open.feishu.cn)
App ID: cli_xxxxxxxxxxxx  ← 粘贴飞书 App ID
App Secret: xxxxxxxxxxxxxxxx  ← 粘贴飞书 App Secret
允许的 open_id (逗号分隔，留空=配对模式): [直接回车]  ← 推荐配对模式
```

#### 4.4 等待安装完成

安装过程约 5-10 分钟，脚本会自动：

1. ✅ 安装系统依赖（Node.js、nginx 等）
2. ✅ 安装飞书插件
3. ✅ 构建项目
4. ✅ 配置 nginx
5. ✅ 创建 systemd 服务
6. ✅ 启动 Moltbot

#### 4.5 记录管理后台地址

安装完成后会显示：

```
════════════════════════════════════════════════════════
                    安装完成！
════════════════════════════════════════════════════════

管理后台访问地址:
  http://你的服务器IP/ui/?token=moltbot-xxxxxxxx

接入说明:
  飞书:     使用长连接模式，在飞书开放平台选择【长连接】并订阅 im.message.receive_v1

服务状态:
  Moltbot: 运行中
  Nginx:   运行中
```

> ⚠️ **重要**: 请保存好管理后台地址和 token！

---

### 5. 验证部署

#### 5.1 检查服务状态

```bash
# 查看服务状态
sudo systemctl status moltbot

# 应该显示: active (running)
```

#### 5.2 检查飞书连接

```bash
cd ~/moltbot
pnpm moltbot channels status

# 应该显示:
# - Feishu default: enabled, configured, running
```

#### 5.3 测试对话

1. 在飞书中搜索你的应用名称（如「Kimi 智能助手」）
2. 点击进入应用
3. 点击「添加」→「添加到聊天」
4. 发送测试消息: `你好`

**预期结果**: 机器人回复 AI 生成的消息

#### 5.4 查看日志

如果遇到问题，查看日志：

```bash
# 实时查看日志
sudo journalctl -u moltbot -f

# 查看最近 50 行日志
sudo journalctl -u moltbot -n 50 --no-pager
```

---

## 使用说明

### 基本对话

在飞书中直接给机器人发消息即可：

```
用户: 介绍一下你自己
机器人: 我是基于 Kimi 2.5 大模型的 AI 助手...
```

### 群聊使用

1. 将机器人添加到群聊
2. 在群里 @机器人 + 消息：

```
用户: @Kimi智能助手 今天天气怎么样？
机器人: [回复]
```

### 配对模式

如果使用配对模式（默认）：

1. 首次使用时发送任意消息
2. 机器人会返回配对码
3. 管理员在后台批准配对：
   ```bash
   cd ~/moltbot
   pnpm moltbot pairing approve feishu <open_id>
   ```

### 访问管理后台

浏览器打开安装时记录的地址：

```
http://你的服务器IP/ui/?token=moltbot-xxxxxxxx
```

可以查看：
- 服务状态
- 对话历史
- 配置管理

---

## 常见问题

### Q1: 机器人不回复消息

**检查清单**:

1. ✅ 飞书事件订阅是否选择了「长连接」模式？
2. ✅ 是否订阅了 `im.message.receive_v1` 事件？
3. ✅ 服务是否正常运行？
   ```bash
   sudo systemctl status moltbot
   pnpm moltbot channels status
   ```
4. ✅ 查看日志是否有错误：
   ```bash
   sudo journalctl -u moltbot -n 100 --no-pager
   ```

### Q2: "No API key found" 错误

**解决方法**:

1. 检查 API Key 配置：
   ```bash
   cd ~/moltbot
   pnpm moltbot config get env.MOONSHOT_API_KEY
   ```

2. 如果为空，重新配置：
   ```bash
   pnpm moltbot config set env.MOONSHOT_API_KEY "sk-xxxxx"
   ```

3. 重启服务：
   ```bash
   sudo systemctl restart moltbot
   ```

### Q3: 飞书配置了但显示 "not configured"

**原因**: 插件冲突或配置未生效

**解决方法**:

```bash
cd ~/moltbot

# 删除源码中的旧飞书插件（如果存在）
mv extensions/feishu /tmp/feishu-old 2>/dev/null || true

# 确认已安装插件
pnpm moltbot plugins list

# 重启服务
sudo systemctl restart moltbot
```

### Q4: 端口 80 被占用

**解决方法**:

```bash
# 检查占用进程
sudo lsof -i :80

# 停止占用服务（假设是 apache2）
sudo systemctl stop apache2
sudo systemctl disable apache2

# 重启 nginx
sudo systemctl restart nginx
```

### Q5: 服务器重启后机器人无法使用

**原因**: 服务未设置开机自启

**解决方法**:

```bash
# 启用开机自启
sudo systemctl enable moltbot
sudo systemctl enable nginx

# 立即启动
sudo systemctl start moltbot
sudo systemctl start nginx
```

### Q6: Kimi API 余额不足

**现象**: 日志显示 `insufficient balance` 或 `quota exceeded`

**解决方法**:

1. 访问 https://platform.moonshot.cn
2. 进入「账户管理」→「充值」
3. 充值后无需重启，立即生效

### Q7: 重复插件警告

**现象**: 日志中大量 `duplicate plugin id detected` 警告

**解决方法**:

```bash
cd ~/moltbot

# 移除源码中的飞书扩展
mv extensions/feishu /tmp/feishu-backup

# 重启服务
sudo systemctl restart moltbot
```

---

## 更新维护

### 更新代码

```bash
cd ~/moltbot

# 拉取最新代码
git pull

# 安装依赖
pnpm install

# 重新构建
pnpm build

# 重启服务
sudo systemctl restart moltbot
```

### 重新配置

如需重新配置（如更换 API Key）：

```bash
cd ~/moltbot
bash scripts/install.sh
```

选择需要重新配置的项目即可。

### 备份配置

```bash
# 备份配置文件
cp ~/.moltbot/config.json5 ~/moltbot-config-backup.json5

# 备份认证文件
cp ~/.moltbot/agents/main/agent/auth-profiles.json ~/auth-profiles-backup.json
```

### 停止服务

```bash
# 临时停止
sudo systemctl stop moltbot

# 禁用开机自启
sudo systemctl disable moltbot
```

### 卸载

```bash
# 停止并删除服务
sudo systemctl stop moltbot
sudo systemctl disable moltbot
sudo rm /etc/systemd/system/moltbot.service

# 删除 nginx 配置
sudo rm /etc/nginx/sites-enabled/moltbot
sudo systemctl restart nginx

# 删除项目文件（可选）
rm -rf ~/moltbot
rm -rf ~/.moltbot
```

---

## 技术支持

- **项目仓库**: https://github.com/MindDock/moltbot
- **问题反馈**: https://github.com/MindDock/moltbot/issues
- **飞书开放平台**: https://open.feishu.cn
- **Kimi 开放平台**: https://platform.moonshot.cn

---

## 许可证

MIT License

---

**祝你使用愉快！🎉**

如有问题，欢迎提 Issue 或 PR。
