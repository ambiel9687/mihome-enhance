#!/bin/bash
# update-loop.sh - 配置更新循环脚本
# 功能：
# 1. 在后台持续运行
# 2. 定期调用 update-config.sh 更新配置
# 3. 记录更新结果
# 4. 支持优雅退出

set -euo pipefail

LOG_PREFIX="[UPDATE-LOOP]"

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

# ==================== 信号处理 ====================
cleanup() {
  log ""
  log "🛑 更新循环收到退出信号"
  log "👋 更新循环已停止"
  exit 0
}

trap cleanup SIGTERM SIGINT

# ==================== 格式化时间间隔 ====================
format_duration() {
  local seconds=$1
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local secs=$((seconds % 60))

  if [ $hours -gt 0 ]; then
    echo "${hours}小时${minutes}分钟"
  elif [ $minutes -gt 0 ]; then
    echo "${minutes}分钟${secs}秒"
  else
    echo "${secs}秒"
  fi
}

# ==================== 主循环 ====================
main() {
  # 获取配置
  local update_interval="${UPDATE_INTERVAL:-3600}"
  local initial_delay="${INITIAL_UPDATE_DELAY:-300}"

  log "=========================================="
  log "⏰ 配置更新循环已启动"
  log "=========================================="
  log "📋 更新策略："
  log "   首次延迟: $(format_duration $initial_delay)"
  log "   更新间隔: $(format_duration $update_interval)"
  log "=========================================="

  # 首次启动延迟（避免与初始化冲突）
  if [ "$initial_delay" -gt 0 ]; then
    log "⏳ 首次更新将在 $(format_duration $initial_delay) 后执行"
    log "   （允许 Mihomo 完成初始化）"
    sleep "$initial_delay"
  fi

  # 计数器
  local update_count=0
  local success_count=0
  local fail_count=0
  local skip_count=0

  # 无限循环
  while true; do
    update_count=$((update_count + 1))

    log ""
    log "=========================================="
    log "🔄 第 ${update_count} 次配置更新"
    log "   开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "=========================================="

    # 记录开始时间（用于计算耗时）
    local start_time=$(date +%s)

    # 执行更新
    if /usr/local/bin/update-config.sh; then
      local exit_code=$?

      # 判断是更新成功还是无变化
      if [ $exit_code -eq 0 ]; then
        # 检查日志中是否包含"无变化"
        success_count=$((success_count + 1))
        log_success "配置更新完成"
      fi
    else
      fail_count=$((fail_count + 1))
      log_error "配置更新失败"
    fi

    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "=========================================="
    log "📊 更新统计："
    log "   本次耗时: ${duration}秒"
    log "   总更新次数: ${update_count}"
    log "   成功: ${success_count} | 失败: ${fail_count}"
    log "=========================================="

    # 计算下次更新时间
    local next_update=$(date -d "@$((end_time + update_interval))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                        date -r $((end_time + update_interval)) '+%Y-%m-%d %H:%M:%S')

    log "⏰ 下次更新时间: ${next_update}"
    log "   （$(format_duration $update_interval) 后）"
    log ""

    # 睡眠等待下次更新
    sleep "$update_interval"
  done
}

# 执行主循环
main "$@"
