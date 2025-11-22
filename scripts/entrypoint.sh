#!/bin/bash
# entrypoint.sh - Mihomo 自动更新容器启动脚本
# 功能：
# 1. 验证环境变量
# 2. 生成初始配置（首次启动）
# 3. 启动 Mihomo 主进程
# 4. 启动配置更新循环
# 5. 处理优雅退出

set -euo pipefail

# ==================== 配置常量 ====================
CONFIG_FILE="/data/config.yaml"
LOG_PREFIX="[MIHOMO-ENHANCE]"

# ==================== 日志函数 ====================
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} $*"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ERROR: $*" >&2
}

log_success() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ✅ $*"
}

log_warning() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ⚠️  $*"
}

# ==================== 准备保底配置 ====================
prepare_default_config() {
  # 如果设置了保底配置且配置文件不存在，则先写入保底配置
  if [ -n "${DEFAULT_CONFIG_YAML:-}" ] && [ ! -f "$CONFIG_FILE" ]; then
    log "📦 检测到保底配置，准备写入..."

    # 确保目录存在
    mkdir -p /data

    # 写入保底配置
    echo "$DEFAULT_CONFIG_YAML" > "$CONFIG_FILE"

    if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
      local size=$(stat -f%z "$CONFIG_FILE" 2>/dev/null || stat -c%s "$CONFIG_FILE")
      log_success "保底配置已准备"
      log "   配置文件: $CONFIG_FILE"
      log "   文件大小: ${size} bytes"
    else
      log_warning "保底配置写入失败，将尝试下载订阅配置"
    fi
  fi
}

# ==================== 配置 Hosts ====================
setup_hosts() {
  # 检查是否设置了 ENV_HOSTS 环境变量
  if [ -z "${ENV_HOSTS:-}" ]; then
    log "ℹ️  未设置 ENV_HOSTS 环境变量，跳过 hosts 配置"
    return 0
  fi

  log "🔧 配置自定义 hosts..."

  local added_count=0
  local skipped_count=0
  local error_count=0

  # 逐行解析 ENV_HOSTS
  while IFS= read -r line || [ -n "$line" ]; do
    # 跳过空行和注释行
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # 解析 IP 和 hostname
    local ip=$(echo "$line" | awk '{print $1}')
    local hostname=$(echo "$line" | awk '{print $2}')

    # 验证格式
    if [ -z "$ip" ] || [ -z "$hostname" ]; then
      log_warning "无效的 hosts 条目格式（已跳过）: $line"
      ((error_count++))
      continue
    fi

    # 检查 hostname 是否已存在
    if ! grep -q "$hostname" /etc/hosts; then
      echo "$ip $hostname" >> /etc/hosts
      log_success "已添加 hosts 条目: $ip $hostname"
      ((added_count++))
    else
      log "ℹ️  hosts 条目 $hostname 已存在，跳过"
      ((skipped_count++))
    fi
  done <<< "$ENV_HOSTS"

  # 打印统计信息
  log "📊 Hosts 配置完成: 新增 $added_count 条，跳过 $skipped_count 条，错误 $error_count 条"
}

# ==================== 环境变量验证 ====================
validate_environment() {
  log "🔍 验证环境配置..."

  # 必需变量检查
  if [ -z "$SUBSCRIBE_URL" ]; then
    log_error "SUBSCRIBE_URL 环境变量未设置"
    log_error ""
    log_error "使用方法："
    log_error "  docker run -e SUBSCRIBE_URL=https://your-subscription-url \\"
    log_error "             ghcr.io/your-username/mihomo-enhance:latest"
    log_error ""
    exit 1
  fi

  # 端口范围验证
  if [ "$START_PORT" -lt 1 ] || [ "$START_PORT" -gt 65535 ]; then
    log_error "START_PORT 必须在 1-65535 范围内，当前值: $START_PORT"
    exit 1
  fi

  # 更新间隔验证
  if [ "$UPDATE_INTERVAL" -lt 60 ]; then
    log_warning "UPDATE_INTERVAL 小于 60 秒可能导致频繁请求，建议 >= 3600"
  fi

  log_success "环境配置验证通过"
}

# ==================== 打印启动信息 ====================
print_startup_info() {
  log "=========================================="
  log "🚀 Mihomo 自动更新容器启动中..."
  log "=========================================="
  log "📋 配置信息："
  log "   订阅地址: ${SUBSCRIBE_URL:0:50}..."
  log "   更新间隔: ${UPDATE_INTERVAL}秒 ($(($UPDATE_INTERVAL / 3600))小时)"
  log "   起始端口: ${START_PORT}"
  log "   API 密钥: ${API_SECRET:0:3}***"
  log "   时区设置: ${TZ}"

  if [ -n "$AUTH_USER" ]; then
    log "   Socks5认证: 已启用 (用户: $AUTH_USER)"
  else
    log "   Socks5认证: 未启用"
  fi

  log "=========================================="
}

# ==================== 初始配置生成 ====================
generate_initial_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log "📥 首次启动，正在下载初始配置..."

    if /usr/local/bin/update-config.sh; then
      log_success "初始配置已生成"
    else
      log_error "初始配置下载失败"
      log_error "订阅地址: ${SUBSCRIBE_URL:0:50}..."
      log_error ""
      log_error "解决方案："
      log_error "1. 检查网络连接和订阅地址是否正确"
      log_error "2. 设置 DEFAULT_CONFIG_YAML 环境变量作为保底配置"
      exit 1
    fi
  else
    log "ℹ️  检测到已存在配置文件，跳过初始化"
  fi
}

# ==================== 信号处理 ====================
cleanup() {
  log ""
  log "🛑 收到退出信号，正在停止服务..."

  # 发送 TERM 信号给子进程
  if [ -n "${MIHOMO_PID:-}" ]; then
    log "   停止 Mihomo 进程 (PID: $MIHOMO_PID)..."
    kill -TERM "$MIHOMO_PID" 2>/dev/null || true
  fi

  if [ -n "${UPDATE_PID:-}" ]; then
    log "   停止更新循环 (PID: $UPDATE_PID)..."
    kill -TERM "$UPDATE_PID" 2>/dev/null || true
  fi

  # 等待进程退出
  wait "$MIHOMO_PID" "$UPDATE_PID" 2>/dev/null || true

  log_success "所有服务已停止"
  log "👋 再见！"
  exit 0
}

# 注册信号处理器
trap cleanup SIGTERM SIGINT

# ==================== 启动 Mihomo ====================
start_mihomo() {
  log "🌐 启动 Mihomo 核心..."

  # 后台启动 mihomo
  /mihomo -f "$CONFIG_FILE" &
  MIHOMO_PID=$!

  # 等待 Mihomo 启动
  log "   等待 Mihomo 初始化..."
  sleep 3

  # 检查进程是否存活
  if ! kill -0 "$MIHOMO_PID" 2>/dev/null; then
    log_error "Mihomo 启动失败"
    log_error "请检查配置文件格式是否正确"
    exit 1
  fi

  # 尝试访问 API 验证启动成功
  local retry=0
  local max_retry=5
  while [ $retry -lt $max_retry ]; do
    if curl -f -s -m 2 "http://localhost:9090/version" \
        -H "Authorization: Bearer ${API_SECRET}" >/dev/null 2>&1; then
      break
    fi
    retry=$((retry + 1))
    sleep 1
  done

  if [ $retry -eq $max_retry ]; then
    log_warning "无法连接到 Mihomo API，但进程正在运行"
  fi

  log_success "Mihomo 已启动"
  log "   进程 PID: $MIHOMO_PID"
  log "   API 地址: http://localhost:9090"
  log "   代理端口: ${START_PORT}+"
}

# ==================== 启动更新循环 ====================
start_update_loop() {
  log "⏰ 启动配置更新循环..."

  /usr/local/bin/update-loop.sh &
  UPDATE_PID=$!

  # 验证进程启动
  sleep 1
  if ! kill -0 "$UPDATE_PID" 2>/dev/null; then
    log_error "更新循环启动失败"
    exit 1
  fi

  log_success "更新循环已启动"
  log "   进程 PID: $UPDATE_PID"
  log "   首次更新: ${INITIAL_UPDATE_DELAY}秒后"
  log "   更新间隔: ${UPDATE_INTERVAL}秒"
}

# ==================== 打印启动完成信息 ====================
print_startup_complete() {
  log "=========================================="
  log "🎉 所有服务启动完成"
  log "=========================================="
  log "📡 服务访问："
  log "   Mihomo API: http://localhost:9090"
  log "   API 密钥: ${API_SECRET}"
  log "   Socks5端口: ${START_PORT} 起"
  log ""
  log "📊 监控命令："
  log "   查看日志: docker logs -f <container_name>"
  log "   健康检查: docker inspect --format='{{.State.Health.Status}}' <container_name>"
  log "   手动更新: docker exec <container_name> /usr/local/bin/update-config.sh"
  log ""
  log "🔧 API 使用示例："
  log "   curl -H 'Authorization: Bearer ${API_SECRET}' http://localhost:9090/proxies"
  log "=========================================="
  log "ℹ️  容器正在运行，按 Ctrl+C 停止..."
}

# ==================== 监控主进程 ====================
monitor_mihomo_process() {
  # 等待 Mihomo 进程退出
  wait "$MIHOMO_PID"
  EXIT_CODE=$?

  log ""
  log_error "⚠️  Mihomo 进程意外退出！"
  log_error "   退出码: $EXIT_CODE"
  log_error "   时间: $(date '+%Y-%m-%d %H:%M:%S')"

  # 停止更新循环
  if [ -n "${UPDATE_PID:-}" ]; then
    kill -TERM "$UPDATE_PID" 2>/dev/null || true
  fi

  exit $EXIT_CODE
}

# ==================== 主流程 ====================
main() {
  # 1. 准备保底配置（如果存在）
  prepare_default_config

  # 2. 配置 hosts
  setup_hosts

  # 3. 验证环境
  validate_environment

  # 4. 打印启动信息
  print_startup_info

  # 5. 生成初始配置
  generate_initial_config

  # 6. 启动 Mihomo
  start_mihomo

  # 7. 启动更新循环
  start_update_loop

  # 8. 打印完成信息
  print_startup_complete

  # 9. 监控主进程
  monitor_mihomo_process
}

# 执行主流程
main "$@"
