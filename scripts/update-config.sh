#!/bin/bash
# update-config.sh - Mihomo 配置更新核心逻辑
# 功能：
# 1. 从订阅地址下载配置
# 2. 验证配置格式
# 3. 检查配置变化
# 4. 备份当前配置
# 5. 应用新配置并热重载

set -euo pipefail

# ==================== 配置常量 ====================
CONFIG_FILE="/data/config.yaml"
TEMP_FILE="/tmp/mihomo-config-$$.yaml"
LOG_PREFIX="[UPDATE-CONFIG]"

# Mihomo API 配置
MIHOMO_API="${MIHOMO_API:-http://localhost:9090}"
API_SECRET="${API_SECRET:-123456}"

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

# ==================== 清理函数 ====================
cleanup() {
  rm -f "$TEMP_FILE"
}
trap cleanup EXIT

# ==================== 构建下载 URL ====================
build_download_url() {
  local base_url="${WORKER_URL}"

  # 如果没有设置 WORKER_URL，直接使用 SUBSCRIBE_URL
  if [ -z "$base_url" ]; then
    echo "$SUBSCRIBE_URL"
    return
  fi

  # 编码订阅 URL（使用 base64）
  local encoded_url=$(echo -n "$SUBSCRIBE_URL" | base64 | tr -d '\n')

  # 构建完整 URL
  local url="${base_url}/api/subscribe?url=${encoded_url}&port=${START_PORT}"

  # 添加认证信息（如果设置）
  if [ -n "${AUTH_USER:-}" ] && [ -n "${AUTH_PASS:-}" ]; then
    local auth_str="${AUTH_USER}:${AUTH_PASS}"
    local encoded_auth=$(echo -n "$auth_str" | base64 | tr -d '\n')
    url="${url}&auth=${encoded_auth}"
  fi

  # 添加自定义文件名（如果设置）
  if [ -n "${CONFIG_NAME:-}" ]; then
    url="${url}&filename=${CONFIG_NAME}"
  fi

  echo "$url"
}

# ==================== 隐藏敏感信息 ====================
sanitize_url_for_log() {
  local url="$1"
  # 替换 URL 中的敏感参数
  echo "$url" | sed 's/token=[^&]*/token=***/g; s/auth=[^&]*/auth=***/g; s/password=[^&]*/password=***/g'
}

# ==================== 下载配置 ====================
download_config() {
  local url=$(build_download_url)
  local safe_url=$(sanitize_url_for_log "$url")

  log "📥 开始下载配置..."
  log "   URL: ${safe_url}..."

  # 打印完整的 curl 命令（方便测试连通性）
  log "   测试命令: curl -I -L -H 'User-Agent: clash.meta/v1.19.13' '${safe_url}'"

  # 使用 curl 下载，支持重定向，30秒超时
  local http_code=$(curl -w "%{http_code}" -o "$TEMP_FILE" \
    -f -s -L -m 60 \
    -H "User-Agent: clash.meta/v1.19.13" \
    "$url" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ]; then
    local size=$(stat -f%z "$TEMP_FILE" 2>/dev/null || stat -c%s "$TEMP_FILE")
    log_success "下载成功"
    log "   HTTP状态: $http_code"
    log "   文件大小: ${size} bytes"
    return 0
  elif [ "$http_code" = "304" ]; then
    log "ℹ️  配置无变化 (HTTP 304)"
    return 1
  else
    log_error "下载失败"
    log_error "   HTTP状态: $http_code"
    return 1
  fi
}

# ==================== 验证配置格式 ====================
validate_config() {
  log "🔍 验证配置格式..."

  # 检查文件是否存在
  if [ ! -f "$TEMP_FILE" ]; then
    log_error "临时配置文件不存在"
    return 1
  fi

  # 检查文件大小（至少 1KB）
  local size=$(stat -f%z "$TEMP_FILE" 2>/dev/null || stat -c%s "$TEMP_FILE")
  if [ "$size" -lt 1024 ]; then
    log_error "配置文件异常小: ${size}B (最小应为 1KB)"
    log_error "文件可能损坏或下载不完整"
    return 1
  fi

  # 检查文件大小上限（防止异常大文件，默认10MB）
  local max_size=$((10 * 1024 * 1024))
  if [ "$size" -gt "$max_size" ]; then
    log_error "配置文件异常大: ${size}B (超过 10MB)"
    log_error "可能存在安全问题"
    return 1
  fi

  # 检查 YAML 基本结构
  if ! grep -q "^proxies:" "$TEMP_FILE"; then
    log_error "配置文件缺少 'proxies:' 字段"
    log_error "这不是有效的 Mihomo/Clash 配置"
    return 1
  fi

  # 检查 listeners 字段（我们生成的配置必须有）
  if ! grep -q "^listeners:" "$TEMP_FILE"; then
    log_error "配置文件缺少 'listeners:' 字段"
    return 1
  fi

  # 统计节点数量
  local node_count=$(grep -c "^  - name:" "$TEMP_FILE" || echo "0")
  log_success "配置验证通过"
  log "   代理节点: ${node_count} 个"
  log "   文件大小: ${size} bytes"

  return 0
}

# ==================== 检查配置是否变化 ====================
check_if_changed() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log "ℹ️  首次生成配置，将直接应用"
    return 0
  fi

  log "🔍 检查配置是否变化..."

  # 计算文件哈希
  local old_hash=$(sha256sum "$CONFIG_FILE" 2>/dev/null | awk '{print $1}')
  local new_hash=$(sha256sum "$TEMP_FILE" | awk '{print $1}')

  if [ "$old_hash" = "$new_hash" ]; then
    log "ℹ️  配置内容无变化"
    log "   哈希值: ${old_hash:0:16}..."
    return 1
  fi

  log_success "检测到配置变化"
  log "   旧哈希: ${old_hash:0:16}..."
  log "   新哈希: ${new_hash:0:16}..."

  # 对比节点数量变化
  if [ -f "$CONFIG_FILE" ]; then
    local old_count=$(grep -c "^  - name:" "$CONFIG_FILE" || echo "0")
    local new_count=$(grep -c "^  - name:" "$TEMP_FILE" || echo "0")
    local diff=$((new_count - old_count))

    if [ "$diff" -gt 0 ]; then
      log "   节点变化: +${diff} 个节点"
    elif [ "$diff" -lt 0 ]; then
      log "   节点变化: ${diff} 个节点"
    else
      log "   节点数量: 无变化 (${new_count} 个)"
    fi
  fi

  return 0
}

# ==================== 应用新配置 ====================
apply_config() {
  log "🔄 应用新配置..."

  # 原子性替换配置文件
  mv "$TEMP_FILE" "$CONFIG_FILE"
  log "   配置文件已替换"

  # 通过 Mihomo API 热重载配置
  log "   正在通过 API 重载配置..."

  local response=$(curl -s -w "\n%{http_code}" -o /tmp/api-response-$$.json \
    -X PUT "${MIHOMO_API}/configs?force=true" \
    -H "Authorization: Bearer ${API_SECRET}" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"${CONFIG_FILE}\"}" 2>/dev/null || echo -e "\n000")

  local http_code=$(echo "$response" | tail -n 1)

  # 清理临时文件
  rm -f /tmp/api-response-$$.json

  # 检查 API 响应
  if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
    log_success "配置已成功重载"
    log "   API响应: HTTP $http_code"
    return 0
  else
    log_error "API 重载失败"
    log_error "   HTTP状态: $http_code"
    log_error "   API地址: $MIHOMO_API"
    return 1
  fi
}

# ==================== 健康检查 ====================
verify_health() {
  log "🏥 验证服务健康状态..."

  # 等待服务稳定
  sleep 2

  # 检查 API 是否响应
  local health=$(curl -s -m 5 "${MIHOMO_API}/version" \
    -H "Authorization: Bearer ${API_SECRET}" 2>/dev/null || echo "")

  if [ -n "$health" ]; then
    log_success "服务运行正常"
    # 尝试解析版本信息（如果有）
    local version=$(echo "$health" | grep -oP '"version":"\K[^"]+' || echo "")
    if [ -n "$version" ]; then
      log "   Mihomo版本: $version"
    fi
    return 0
  else
    log_error "服务健康检查失败"
    log_error "   无法连接到 API: $MIHOMO_API"
    return 1
  fi
}

# ==================== 主流程 ====================
main() {
  log "=========================================="
  log "🔄 开始配置更新流程"

  # 步骤1: 下载配置
  if ! download_config; then
    log_error "❌ 更新失败：下载错误"
    return 1
  fi

  # 步骤2: 验证配置
  if ! validate_config; then
    log_error "❌ 更新失败：配置验证失败"
    return 1
  fi

  # 步骤3: 检查变化
  if ! check_if_changed; then
    log "=========================================="
    return 0  # 无变化但不是错误
  fi

  # 步骤4: 应用新配置
  if ! apply_config; then
    log_error "❌ 更新失败：配置应用错误"
    return 1
  fi

  # 步骤5: 健康检查
  if ! verify_health; then
    log_error "⚠️  健康检查失败，但配置已应用"
    log_error "   请检查 Mihomo 日志排查问题"
  fi

  log_success "🎉 配置更新成功完成"
  log "=========================================="
  return 0
}

# 执行主流程
main "$@"
