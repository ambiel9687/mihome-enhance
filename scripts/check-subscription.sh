#!/bin/bash
# check-subscription.sh - 检查订阅地址并准备保底配置
# 用途：在容器启动前验证订阅地址是否可访问

set -euo pipefail

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

# 使用说明
usage() {
  cat <<EOF
使用方法：
  $0 <订阅地址> [保底配置文件路径]

参数：
  订阅地址           - 必需，订阅链接
  保底配置文件路径   - 可选，用作保底配置的 config.yaml 文件路径

示例：
  # 仅检查订阅地址
  $0 "https://your-subscription-url"

  # 检查订阅地址并准备保底配置
  $0 "https://your-subscription-url" "./config.yaml"

输出：
  - 如果订阅地址可访问，显示成功信息
  - 如果订阅地址不可访问且提供了保底配置，输出可用于 docker run 的命令
EOF
  exit 1
}

# 参数检查
if [ $# -lt 1 ]; then
  usage
fi

SUBSCRIBE_URL="$1"
DEFAULT_CONFIG_FILE="${2:-}"

# 检查订阅地址
log_info "检查订阅地址可访问性..."
log_info "URL: ${SUBSCRIBE_URL}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
  -H "User-Agent: clash.meta/v1.19.13" \
  "$SUBSCRIBE_URL" || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  log_info "✅ 订阅地址可访问 (HTTP $HTTP_CODE)"
  log_info "建议：可以直接使用此订阅地址启动容器"
  echo ""
  cat <<EOF
推荐的启动命令：
docker run -d \\
  --name mihome-enhance \\
  -e SUBSCRIBE_URL="$SUBSCRIBE_URL" \\
  -p 7890:7890 \\
  -p 9090:9090 \\
  --restart unless-stopped \\
  ghcr.io/YOUR_USERNAME/mihome-enhance:latest
EOF
  exit 0
else
  log_error "❌ 订阅地址不可访问 (HTTP $HTTP_CODE)"

  if [ -z "$DEFAULT_CONFIG_FILE" ]; then
    log_error "未提供保底配置文件"
    log_error ""
    log_error "建议："
    log_error "1. 检查订阅地址是否正确"
    log_error "2. 检查网络连接"
    log_error "3. 提供保底配置文件: $0 \"$SUBSCRIBE_URL\" /path/to/config.yaml"
    exit 1
  fi

  # 检查保底配置文件
  if [ ! -f "$DEFAULT_CONFIG_FILE" ]; then
    log_error "保底配置文件不存在: $DEFAULT_CONFIG_FILE"
    exit 1
  fi

  log_warning "将使用保底配置启动"
  log_info "保底配置文件: $DEFAULT_CONFIG_FILE"

  # 读取配置文件内容
  if ! CONFIG_YAML=$(cat "$DEFAULT_CONFIG_FILE"); then
    log_error "无法读取保底配置文件"
    exit 1
  fi

  # 验证配置文件不为空
  if [ -z "$CONFIG_YAML" ]; then
    log_error "保底配置文件为空"
    exit 1
  fi

  log_info "✅ 保底配置已准备"
  log_info "配置大小: $(echo "$CONFIG_YAML" | wc -c) bytes"
  echo ""

  cat <<'EOF'
推荐的启动命令（使用保底配置）：

# 方式1: 使用脚本变量
CONFIG_YAML=$(cat /path/to/config.yaml)

docker run -d \
  --name mihome-enhance \
  -e SUBSCRIBE_URL="订阅地址" \
  -e DEFAULT_CONFIG_YAML="$CONFIG_YAML" \
  -p 7890:7890 \
  -p 9090:9090 \
  --restart unless-stopped \
  ghcr.io/YOUR_USERNAME/mihome-enhance:latest

# 方式2: 直接在命令中读取
docker run -d \
  --name mihome-enhance \
  -e SUBSCRIBE_URL="订阅地址" \
  -e DEFAULT_CONFIG_YAML="$(cat /path/to/config.yaml)" \
  -p 7890:7890 \
  -p 9090:9090 \
  --restart unless-stopped \
  ghcr.io/YOUR_USERNAME/mihome-enhance:latest
EOF

  log_info ""
  log_info "注意："
  log_info "- 容器启动时会优先尝试下载订阅配置"
  log_info "- 如果下载失败，将使用保底配置"
  log_info "- 后续更新周期会继续尝试下载最新配置"

  exit 0
fi
