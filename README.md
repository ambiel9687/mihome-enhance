# Mihomo 自动更新容器

![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)

基于 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 的增强版 Docker 镜像，支持订阅配置自动更新。

## ✨ 核心特性

- 🔄 **自动更新**：容器内定期自动更新订阅配置，无需手动干预
- 🔥 **热重载**：通过 Mihomo API 热重载配置，0 停机时间
- 🌍 **环境变量配置**：符合 12-Factor 原则，所有配置通过环境变量管理
- 📦 **开箱即用**：一条命令启动，自动初始化配置
- 🏥 **健康检查**：内置健康检查，自动重启故���容器
- 💾 **配置持久化**：自动备份配置文件，支持回滚
- 🔒 **安全可靠**：日志中自动屏蔽敏感信息
- 🚀 **多架构支持**：支持 amd64 和 arm64 架构

## 🎯 使用场景

- ✅ 需要自动更新订阅配置的场景
- ✅ 容器化部署 Mihomo 代理
- ✅ 保持"一节点一端口"的固定映射模型
- ✅ 服务器或 NAS 等长期运行的环境

## 📦 快速开始

### 方式 1：Docker Run（推荐快速测试）

```bash
docker run -d \
  --name mihomo-auto \
  -e SUBSCRIBE_URL="https://your-subscription-url" \
  -v mihomo-data:/data \
  -p 7890:7890 \
  -p 9090:9090 \
  --restart unless-stopped \
  ghcr.io/YOUR_USERNAME/mihomo-auto:latest
```

### 方式 2：Docker Compose（推荐生产使用）

1. **创建 docker-compose.yml**

```yaml
version: '3.8'

services:
  mihomo:
    image: ghcr.io/YOUR_USERNAME/mihomo-auto:latest
    container_name: mihomo-auto
    restart: unless-stopped
    environment:
      - SUBSCRIBE_URL=https://your-subscription-url
      - UPDATE_INTERVAL=3600
      - START_PORT=42000
      - API_SECRET=wangzh
      - TZ=Asia/Shanghai
    volumes:
      - ./data:/data
    ports:
      - "7890:7890"
      - "9090:9090"
```

2. **启动服务**

```bash
docker-compose up -d
```

3. **查看日志**

```bash
docker-compose logs -f mihomo
```

## ⚙️ 环境变量配置

### 必需配置

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `SUBSCRIBE_URL` | 订阅地址 | `https://example.com/subscription` |

### 可选配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `WORKER_URL` | - | Workers 转换服务地址（如果使用） |
| `UPDATE_INTERVAL` | `3600` | 更新间隔（秒）|
| `START_PORT` | `42000` | Socks5 起始端口 |
| `API_SECRET` | `wangzh` | Mihomo API 密钥 |
| `AUTH_USER` | - | Socks5 认证用户名 |
| `AUTH_PASS` | - | Socks5 认证密码 |
| `CONFIG_NAME` | - | 自定义配置名称 |
| `LOG_LEVEL` | `info` | 日志级别 |
| `INITIAL_UPDATE_DELAY` | `300` | 首次更新延迟（秒）|
| `TZ` | `Asia/Shanghai` | 时区设置 |

### 完整配置示例

```bash
docker run -d \
  --name mihomo-auto \
  -e SUBSCRIBE_URL="https://your-subscription-url" \
  -e WORKER_URL="https://your-worker.workers.dev" \
  -e UPDATE_INTERVAL=3600 \
  -e START_PORT=42000 \
  -e API_SECRET="your-secret" \
  -e AUTH_USER="user" \
  -e AUTH_PASS="pass" \
  -e CONFIG_NAME="my-config" \
  -e TZ="Asia/Shanghai" \
  -v mihomo-data:/data \
  -p 7890:7890 \
  -p 9090:9090 \
  --restart unless-stopped \
  ghcr.io/YOUR_USERNAME/mihomo-auto:latest
```

## 🔧 常用命令

### 查看容器状态

```bash
# 查看运行状态
docker ps | grep mihomo-auto

# 查看健康状态
docker inspect --format='{{.State.Health.Status}}' mihomo-auto

# 查看资源使用
docker stats mihomo-auto
```

### 查看日志

```bash
# 实时日志
docker logs -f mihomo-auto

# 最近 100 行
docker logs --tail 100 mihomo-auto

# 查看时间戳
docker logs -t mihomo-auto
```

### 配置管理

```bash
# 手动触发更新
docker exec mihomo-auto /usr/local/bin/update-config.sh

# 查看当前配置
docker exec mihomo-auto cat /data/config.yaml

# 查看备份列表
docker exec mihomo-auto ls -lh /data/backups/

# 恢复特定备份
docker exec mihomo-auto cp /data/backups/config-20240101-120000.yaml /data/config.yaml
docker restart mihomo-auto
```

### 容器管理

```bash
# 重启容器
docker restart mihomo-auto

# 停止容器
docker stop mihomo-auto

# 删除容器（保留数据）
docker rm mihomo-auto

# 删除容器和数据
docker rm -v mihomo-auto
```

## 📡 API 使用

Mihomo 提供 RESTful API，默认端口 `9090`。

### 认证

所有 API 请求需要携带认证头：

```bash
Authorization: Bearer your-secret
```

### 常用 API

```bash
# API 密钥
API_SECRET="wangzh"

# 查看版本信息
curl -H "Authorization: Bearer ${API_SECRET}" \
  http://localhost:9090/version

# 查看所有代理
curl -H "Authorization: Bearer ${API_SECRET}" \
  http://localhost:9090/proxies

# 查看连接状态
curl -H "Authorization: Bearer ${API_SECRET}" \
  http://localhost:9090/connections

# 切换代理
curl -X PUT \
  -H "Authorization: Bearer ${API_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"name":"香港节点1"}' \
  http://localhost:9090/proxies/PROXY

# 重载配置
curl -X PUT \
  -H "Authorization: Bearer ${API_SECRET}" \
  http://localhost:9090/configs?force=true
```

## 🔍 故障排除

### 容器无法启动

**症状**：容器启动后立即退出

**排查步骤**：

1. 检查环境变量是否正确设置

```bash
docker logs mihomo-auto | grep "ERROR"
```

2. 验证订阅地址是否可访问

```bash
curl -I "https://your-subscription-url"
```

3. 检查端口是否被占用

```bash
sudo lsof -i :7890
sudo lsof -i :9090
```

### 配置更新失败

**症状**：日志显示"配置更新失败"

**解决方案**：

1. 检查订阅地址是否有效

```bash
docker exec mihomo-auto curl -I "$SUBSCRIBE_URL"
```

2. 查看详细错误日志

```bash
docker logs mihomo-auto | grep "UPDATE-CONFIG"
```

3. 手动触发更新并观察

```bash
docker exec -it mihomo-auto /usr/local/bin/update-config.sh
```

### API 无法访问

**症状**：无法通过 `localhost:9090` 访问 API

**解决方案**：

1. 检查端口映射

```bash
docker port mihomo-auto
```

2. 验证 API 密钥

```bash
# 查看容器环境变量
docker exec mihomo-auto env | grep API_SECRET
```

3. 测试 API 连接

```bash
docker exec mihomo-auto curl -f http://localhost:9090/version \
  -H "Authorization: Bearer wangzh"
```

### 节点无法连接

**症状**：代理端口无响应

**解决方案**：

1. 检查配置文件

```bash
docker exec mihomo-auto cat /data/config.yaml | grep -A 5 "listeners:"
```

2. 验证 Mihomo 进程

```bash
docker exec mihomo-auto ps aux | grep mihomo
```

3. 重启容器

```bash
docker restart mihomo-auto
```

## 🏗️ 项目结构

```
mihomo-wok/
├── .github/
│   └── workflows/
│       └── build-image.yml    # GitHub Actions 构建流程
├── scripts/
│   ├── entrypoint.sh          # 容器启动脚本
│   ├── update-config.sh       # 配置更新逻辑
│   └── update-loop.sh         # 更新循环脚本
├── Dockerfile                 # Docker 镜像定义
├── docker-compose.yml         # Docker Compose 配置示例
├── .dockerignore              # Docker 构建忽略文件
└── README.md                  # 项目文档
```

## 🚀 自定义构建

### 1. Fork 仓库

```bash
git clone https://github.com/YOUR_USERNAME/mihomo-wok.git
cd mihomo-wok
```

### 2. 修改配置

编辑 `docker-compose.yml` 或 `.github/workflows/build-image.yml`

### 3. 本地构建

```bash
# 构建镜像
docker build -t mihomo-auto:local .

# 测试运行
docker run -d \
  --name mihomo-test \
  -e SUBSCRIBE_URL="https://your-url" \
  -p 7890:7890 \
  -p 9090:9090 \
  mihomo-auto:local
```

### 4. 推送到 GitHub

```bash
git add .
git commit -m "feat: custom configuration"
git push origin main
```

GitHub Actions 将自动构建并推送到 GHCR。

## 📊 监控与日志

### 日志级别

- `debug`: 调试信息（最详细）
- `info`: 一般信息（默认）
- `warning`: 警告信息
- `error`: 错误信息

### 日志格式

```
2024-01-01 12:00:00 [MIHOMO-AUTO] ✅ 配置更新成功
2024-01-01 12:00:05 [UPDATE-CONFIG] 📥 开始下载配置...
2024-01-01 12:00:10 [UPDATE-LOOP] ⏰ 下次更新时间: 2024-01-01 13:00:00
```

### Prometheus 监控（可选）

如需集成 Prometheus 监控，可以：

1. 暴露 Mihomo 自带的 metrics 端点
2. 添加自定义 exporter 收集更新状态

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/amazing-feature`
3. 提交更改：`git commit -m 'feat: add amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) - 优秀的 Clash Meta 内核
- [Clash](https://github.com/Dreamacro/clash) - 原始 Clash 项目

## 🔗 相关链接

- [Mihomo 文档](https://wiki.metacubex.one/)
- [Docker 官方文档](https://docs.docker.com/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)

---

⭐ 如果这个项目对你有帮助，请给个 Star！

📧 有问题或建议？欢迎创建 [Issue](https://github.com/YOUR_USERNAME/mihomo-wok/issues)
