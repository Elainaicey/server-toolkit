#!/usr/bin/env bash

database_install_redis() {
  log_step "安装 Redis"
  pkg_update_index
  [[ "$OS_FAMILY" == "debian" ]] && pkg_install redis-server || pkg_install redis
  systemctl list-unit-files | grep -q '^redis-server\.service' && run systemctl enable --now redis-server || true
  systemctl list-unit-files | grep -q '^redis\.service' && run systemctl enable --now redis || true
  log_warn "不建议将 Redis 直接暴露到公网。"
}

database_install_postgresql() {
  log_step "安装 PostgreSQL"
  pkg_update_index
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install postgresql postgresql-contrib
  else
    pkg_install postgresql-server postgresql-contrib
    [[ -f /var/lib/pgsql/data/PG_VERSION ]] || run postgresql-setup --initdb || true
  fi
  systemctl list-unit-files | grep -q '^postgresql\.service' && run systemctl enable --now postgresql || true
}

database_install_mariadb() {
  log_step "安装 MariaDB"
  pkg_update_index
  [[ "$OS_FAMILY" == "debian" ]] && pkg_install mariadb-server mariadb-client || pkg_install mariadb-server mariadb
  systemctl list-unit-files | grep -q '^mariadb\.service' && run systemctl enable --now mariadb || true
  log_warn "安装后建议执行 mysql_secure_installation。"
}

database_install_sqlite() {
  log_step "安装 SQLite"
  pkg_update_index
  pkg_install sqlite3
}

database_install_from_profile() {
  local dbs="${1:-}"
  local old_ifs="$IFS"
  local arr=()
  IFS=' ' read -r -a arr <<< "$dbs"
  IFS="$old_ifs"
  local db
  for db in "${arr[@]}"; do
    [[ -z "$db" ]] && continue
    case "$db" in
      redis) database_install_redis ;;
      postgresql) database_install_postgresql ;;
      mariadb) database_install_mariadb ;;
      sqlite) database_install_sqlite ;;
      *) log_warn "未知数据库：$db" ;;
    esac
  done
}

database_menu() {
  require_root
  detect_system
  clear_screen
  ui_panel_start "数据库 / 缓存"
  ui_panel_line "[01] Redis"
  ui_panel_line "[02] PostgreSQL"
  ui_panel_line "[03] MariaDB"
  ui_panel_line "[04] SQLite"
  ui_panel_line "[00] 返回"
  ui_panel_end
  printf '\n'
  local selected item arr=()
  selected="$(choose_numbers "请选择编号，多个项目用逗号分隔")"
  [[ -z "$selected" || "$selected" == "0" || "$selected" == "00" ]] && return 0
  IFS=',' read -r -a arr <<< "$selected"
  for item in "${arr[@]}"; do
    case "$item" in
      1|01) database_install_redis ;;
      2|02) database_install_postgresql ;;
      3|03) database_install_mariadb ;;
      4|04) database_install_sqlite ;;
    esac
  done
  pause
}
