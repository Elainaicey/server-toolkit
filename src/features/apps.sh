#!/usr/bin/env bash

apps_service_summary() {
  ui_page "常见应用状态" "Web、数据库、缓存和容器服务"
  local label service
  while IFS='|' read -r label service; do
    if service_exists "$service"; then
      ui_kv "$label" "$(service_state "$service")"
    else
      ui_kv "$label" "未安装"
    fi
  done <<'EOF'
Docker|docker.service
Nginx|nginx.service
Caddy|caddy.service
Redis|redis-server.service
PostgreSQL|postgresql.service
MariaDB|mariadb.service
EOF
}

apps_menu() {
  local choice
  while true; do
    ui_page "应用与容器" "集中管理具有独立运行状态的服务器应用"
    ui_context "软件安装仍保持一次一个；应用操作不会隐式修改防火墙。"
    ui_item 1 "应用状态" "Web、数据库、缓存与容器服务概览"
    ui_item 2 "Docker" "容器、镜像、网络、存储卷与清理"
    ui_item 3 "安装应用" "进入单项软件搜索"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) apps_service_summary; pause ;;
      2) docker_menu ;;
      3) software_catalog_menu ;;
      0) return 0 ;;
      *) warn "未知选项"; pause ;;
    esac
  done
}
