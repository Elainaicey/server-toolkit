#!/usr/bin/env bash

apps_service_catalog() {
  cat <<'EOF'
Docker|docker.service|docker
Nginx|nginx.service|nginx
Caddy|caddy.service|caddy
Apache|apache2.service|apache
Redis|redis-server.service|redis
Memcached|memcached.service|memcached
PostgreSQL|postgresql.service|postgresql
MariaDB|mariadb.service|mariadb
3x-ui|x-ui.service|
EOF
}

apps_service_record() {
  local number="$1"
  apps_service_catalog | awk -F '|' -v number="$number" 'NR == number {print; exit}'
}

apps_service_summary() {
  local label service catalog_id state enabled style count=0 running=0 installed=0
  ui_page "应用服务管理" "统一查看并控制 Web、数据库、缓存和容器服务"
  while IFS='|' read -r label service catalog_id; do
    count=$((count + 1))
    if service_exists "$service"; then
      installed=$((installed + 1))
      state="$(service_state "$service")"
      enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
      enabled="${enabled:-disabled}"
      if [[ "$state" == "active" ]]; then
        style="good"
        running=$((running + 1))
      else
        style="warn"
      fi
      ui_state_item "$count" "$label" "$state" "$style" "$service · 开机启动 $enabled"
    else
      ui_state_item "$count" "$label" "未安装" "muted" "$service"
    fi
  done < <(apps_service_catalog)
  ui_stats "目录" "$count" "已安装" "$installed" "运行中" "$running"
  ui_note "选择已安装应用可查看详情、日志、依赖并控制启动、停止、重启和开机策略。"
  ui_action 0 "返回" "muted"
}

apps_service_manage() {
  local choice record label service catalog_id
  while true; do
    apps_service_summary
    choice="$(read_input "请选择应用" "0")"
    [[ "$choice" == "0" ]] && return 0
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "选项无效。"; pause; continue; }
    record="$(apps_service_record "$choice")"
    [[ -n "$record" ]] || { warn "未知应用编号：$choice"; pause; continue; }
    IFS='|' read -r label service catalog_id <<<"$record"
    if service_exists "$service"; then
      services_select "$service"
    elif [[ -n "$catalog_id" ]]; then
      ui_note "$label 尚未安装，将进入单项软件安装流程。"
      catalog_install "$catalog_id" || true
      pause
    else
      warn "$label 未安装，当前只管理已经存在的 $service。"
      pause
    fi
  done
}

apps_menu() {
  local choice
  while true; do
    ui_page "应用与容器" "集中管理服务器应用、服务生命周期与容器"
    ui_context "软件安装仍保持一次一个；应用操作不会隐式修改防火墙。"
    ui_section "应用服务" "primary"
    ui_item 1 "应用服务管理" "状态、日志、启停、重启与开机策略"
    ui_section "管理入口" "accent"
    ui_item 2 "Docker" "容器、镜像、网络、存储卷与清理"
    ui_item 3 "安装应用" "进入单项软件搜索"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) apps_service_manage ;;
      2) docker_menu ;;
      3) software_catalog_menu ;;
      0) return 0 ;;
      *) warn "未知选项"; pause ;;
    esac
  done
}
