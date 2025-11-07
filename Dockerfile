# Dockerfile - 增强版 Mihomo 镜像
# 基于官方 Mihomo 镜像，添加自动更新订阅功能

FROM metacubex/mihomo:latest


# 安装必要工具
# - curl: 用于下载订阅配置
# - ca-certificates: HTTPS 证书验证
# - bash: 脚本运行环境
# - tzdata: 时区支持
RUN apk add --no-cache \
    curl \
    ca-certificates \
    bash \
    tzdata \
    && rm -rf /var/cache/apk/*

# 复制脚本文件
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/update-config.sh /usr/local/bin/update-config.sh
COPY scripts/update-loop.sh /usr/local/bin/update-loop.sh

# 设置执行权限
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/update-config.sh \
    && chmod +x /usr/local/bin/update-loop.sh

# 环境变量配置（可通过 docker run -e 覆盖）
# 核心配置
ENV SUBSCRIBE_URL="" \
    UPDATE_INTERVAL=28800 \
    START_PORT=42000 \
    API_SECRET="123456"

# 可选配置
ENV AUTH_USER="" \
    AUTH_PASS="" \
    LOG_LEVEL="info" \
    INITIAL_UPDATE_DELAY=300 \
    TZ="Asia/Shanghai" \
    SHOW_FULL_URL="true"

# 保底配置（当网络无法访问订阅地址时使用）
ENV DEFAULT_CONFIG_YAML=""

# Mihomo API 配置
ENV MIHOMO_API="http://localhost:9090"

# 创建配置目录（容器内临时存储）
RUN mkdir -p /data

# 设置工作目录
WORKDIR /data

# 暴露端口
# 7890: Mixed (HTTP + SOCKS5) 代理端口
# 9090: Mihomo RESTful API 端口
# 42000-42100: Socks5 代理端口范围（一节点一端口）
EXPOSE 7890 9090 42000-42100

# 健康检查
# 每30秒检查一次 Mihomo API 是否响应
HEALTHCHECK --interval=30s \
            --timeout=3s \
            --start-period=10s \
            --retries=3 \
  CMD curl -f http://localhost:9090/version \
      -H "Authorization: Bearer ${API_SECRET}" || exit 1

# 容器启动入口
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
