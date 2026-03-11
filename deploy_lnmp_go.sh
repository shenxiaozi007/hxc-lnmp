#!/usr/bin/env bash

###############################################################################
# LNMP + Go 一键部署脚本（CentOS / Rocky，Docker + docker compose）
#
# 使用方式（在服务器上）：
#   1) 上传本脚本到服务器，例如 /root/deploy_lnmp_go.sh
#   2) 赋予执行权限：chmod +x deploy_lnmp_go.sh
#   3) 执行：./deploy_lnmp_go.sh
#
# 执行后会：
#   - 安装并启动 Docker（CentOS/Rocky）
#   - 自动配置常用国内镜像源（Daocloud / 网易 / 腾讯云），解决拉取镜像缓慢或失败问题
#   - 在 /opt/lnmp 下创建目录结构
#   - 生成 docker-compose.yml、Nginx 配置、PHP 示例页面、Go 示例服务与 Dockerfile
#   - 运行：docker compose up -d
#
# 部署完成后访问：
#   - PHP 站点首页：http://你的服务器IP/
#   - Go 服务 API：http://你的服务器IP/api/ping
###############################################################################

set -euo pipefail

#######################################
# 可根据需要调整的变量
#######################################
BASE_DIR="/opt/lnmp"
NGINX_DIR="${BASE_DIR}/nginx"
NGINX_CONF_DIR="${NGINX_DIR}/conf.d"
WWW_DIR="${BASE_DIR}/www"
GO_APP_DIR="${BASE_DIR}/go-app"
DATA_DIR="${BASE_DIR}/data"
MYSQL_DATA_DIR="${DATA_DIR}/mysql"
LOG_DIR="${BASE_DIR}/logs"
NGINX_LOG_DIR="${LOG_DIR}/nginx"

COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

DOCKER_NETWORK_NAME="lnmp_net"

# 数据库配置（生产环境请修改为更安全的密码）
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root123456}"
MYSQL_DATABASE="${MYSQL_DATABASE:-app_db}"
MYSQL_USER="${MYSQL_USER:-app_user}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-app123456}"

# Go 服务端口（容器内部）
GO_APP_PORT="8080"

#######################################
# 工具函数
#######################################

log() {
  echo -e "[LNMP-GO] $*"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log "请使用 root 用户或通过 sudo 执行本脚本。"
    exit 1
  fi
}

detect_pkg_manager() {
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo "yum"
  fi
}

configure_docker_mirror() {
  log "配置 Docker 国内镜像源（Daocloud / 网易 / 腾讯云）..."

  mkdir -p /etc/docker

  cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF

  log "已写入 /etc/docker/daemon.json，如有自有镜像加速地址，可手动修改该文件。"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "检测到 Docker 已安装，将更新国内镜像源配置。"
    configure_docker_mirror
    if systemctl is-active docker >/dev/null 2>&1; then
      systemctl restart docker || true
    fi
    return
  fi

  local pkg_mgr
  pkg_mgr="$(detect_pkg_manager)"

  log "开始安装 Docker（使用 ${pkg_mgr}）..."

  ${pkg_mgr} remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

  ${pkg_mgr} install -y yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

  ${pkg_mgr} install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  # 写入国内镜像源配置
  configure_docker_mirror

  systemctl enable docker
  systemctl start docker

  # 应用新的 daemon.json 配置
  systemctl restart docker

  log "Docker 安装并启动完成。"
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "已检测到 docker compose 插件。"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    log "检测到 docker-compose，可使用 'docker-compose' 命令。"
    return
  fi

  log "未检测到 docker compose，且安装插件可能失败，请检查 Docker 安装。"
  exit 1
}

create_directories() {
  log "创建目录结构..."
  mkdir -p "${NGINX_CONF_DIR}" "${WWW_DIR}" "${GO_APP_DIR}" "${MYSQL_DATA_DIR}" "${NGINX_LOG_DIR}"
}

write_compose_file() {
  if [[ -f "${COMPOSE_FILE}" ]]; then
    log "检测到已存在的 docker-compose.yml，跳过覆盖。"
    return
  fi

  log "生成 docker-compose.yml ..."

  cat > "${COMPOSE_FILE}" <<EOF
version: "3.9"

services:
  nginx:
    image: nginx:stable
    container_name: lnmp-nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./www:/var/www/html
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - php-fpm
      - go-app
    networks:
      - ${DOCKER_NETWORK_NAME}

  php-fpm:
    image: php:8.2-fpm
    container_name: lnmp-php-fpm
    volumes:
      - ./www:/var/www/html
    networks:
      - ${DOCKER_NETWORK_NAME}

  mysql:
    image: mysql:8.4
    container_name: lnmp-mysql
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${MYSQL_DATABASE}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
    command:
      - --default-authentication-plugin=mysql_native_password
    ports:
      # 如不需要对外暴露 MySQL，可注释掉下一行
      - "3306:3306"
    volumes:
      - ./data/mysql:/var/lib/mysql
    networks:
      - ${DOCKER_NETWORK_NAME}

  go-app:
    build:
      context: ./go-app
      dockerfile: Dockerfile
    container_name: lnmp-go-app
    environment:
      # 如需访问 MySQL，可在 Go 代码中使用这些环境变量
      DB_HOST: "mysql"
      DB_PORT: "3306"
      DB_USER: "${MYSQL_USER}"
      DB_PASSWORD: "${MYSQL_PASSWORD}"
      DB_NAME: "${MYSQL_DATABASE}"
    ports:
      # 如只通过 Nginx 访问，可注释此行
      - "8080:8080"
    networks:
      - ${DOCKER_NETWORK_NAME}

networks:
  ${DOCKER_NETWORK_NAME}:
    driver: bridge
EOF
}

write_nginx_main_conf() {
  local file="${NGINX_DIR}/nginx.conf"

  if [[ -f "${file}" ]]; then
    log "检测到已存在的 nginx.conf，跳过覆盖。"
    return
  fi

  log "生成 nginx 主配置 nginx.conf ..."

  cat > "${file}" <<'EOF'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
}
EOF
}

write_nginx_vhost_conf() {
  local file="${NGINX_CONF_DIR}/default.conf"

  if [[ -f "${file}" ]]; then
    log "检测到已存在的 Nginx 虚拟主机配置 default.conf，跳过覆盖。"
    return
  fi

  log "生成 Nginx 虚拟主机配置 default.conf ..."

  cat > "${file}" <<'EOF'
server {
    listen       80;
    server_name  _;

    root   /var/www/html;
    index  index.php index.html index.htm;

    # 静态文件与默认首页
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # PHP 解析
    location ~ \.php$ {
        fastcgi_pass   php-fpm:9000;
        fastcgi_index  index.php;
        include        fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
        fastcgi_param  PATH_INFO        $fastcgi_path_info;
    }

    # 反向代理到 Go 服务
    location /api/ {
        proxy_pass         http://go-app:8080/;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # 日志
    access_log  /var/log/nginx/access.log  main;
    error_log   /var/log/nginx/error.log   warn;
}
EOF
}

write_php_index() {
  local file="${WWW_DIR}/index.php"

  if [[ -f "${file}" ]]; then
    log "检测到已存在的 index.php，跳过覆盖。"
    return
  fi

  log "生成示例 PHP 首页 index.php ..."

  cat > "${file}" <<'EOF'
<?php
phpinfo();
EOF
}

write_go_dockerfile() {
  local file="${GO_APP_DIR}/Dockerfile"

  if [[ -f "${file}" ]]; then
    log "检测到已存在的 go-app Dockerfile，跳过覆盖。"
    return
  fi

  log "生成 Go 应用 Dockerfile ..."

  cat > "${file}" <<'EOF'
FROM golang:1.22-alpine

WORKDIR /app

# 拷贝当前目录下的 Go 源码（示例只有 main.go）
COPY . .

# 编译为二进制
RUN go build -o server main.go

ENV GO_APP_PORT=8080

EXPOSE 8080

CMD ["/app/server"]
EOF
}

write_go_main() {
  local file="${GO_APP_DIR}/main.go"

  if [[ -f "${file}" ]]; then
    log "检测到已存在的 main.go，跳过覆盖。"
    return
  fi

  log "生成 Go 示例服务 main.go ..."

  cat > "${file}" <<'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello from Go app in LNMP stack")
	})

	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "pong")
	})

	port := os.Getenv("GO_APP_PORT")
	if port == "" {
		port = "8080"
	}

	addr := ":" + port
	log.Printf("Go app listening on %s\n", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
EOF
}

docker_compose_up() {
  log "启动容器服务（docker compose up -d）..."
  cd "${BASE_DIR}"

  if docker compose version >/dev/null 2>&1; then
    docker compose up -d
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
  else
    log "未找到 docker compose 或 docker-compose 命令，请检查 Docker 安装。"
    exit 1
  fi
}

main() {
  require_root
  install_docker
  ensure_docker_compose
  create_directories

  write_compose_file
  write_nginx_main_conf
  write_nginx_vhost_conf
  write_php_index
  write_go_dockerfile
  write_go_main

  docker_compose_up

  log "部署完成。"
  echo
  echo "================ 部署信息 ================"
  echo "Web 根目录:       ${WWW_DIR}"
  echo "Go 应用目录:      ${GO_APP_DIR}"
  echo "MySQL 数据目录:   ${MYSQL_DATA_DIR}"
  echo
  echo "访问 PHP 首页:    http://<你的服务器IP>/"
  echo "访问 Go API:      http://<你的服务器IP>/api/ping"
  echo "=========================================="
}

main "$@"

