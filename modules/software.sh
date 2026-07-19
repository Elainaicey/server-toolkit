#!/usr/bin/env bash

software_center_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    ui_panel_start "软件安装中心"
    ui_panel_line "[01] 按单项选择      只安装真正需要的软件（推荐）"
    ui_panel_line "[02] 开发运行时      Python/Node.js/Go/Rust/Java/PHP"
    ui_panel_line "[03] 常用集合        明确选择后才会整组安装"
    ui_panel_rule
    ui_panel_line "[04] Docker 环境     官方仓库与 Compose"
    ui_panel_line "[05] Web 服务        Caddy/Nginx"
    ui_panel_line "[06] 数据库/缓存     Redis/PostgreSQL/MariaDB/SQLite"
    ui_panel_line "[07] 自定义包名      直接使用系统包名"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择分类" "00")"
    case "$choice" in
      1|01) catalog_menu ;;
      2|02) software_runtime_menu ;;
      3|03) software_bundle_menu ;;
      4|04) docker_menu ;;
      5|05) web_menu ;;
      6|06) database_menu ;;
      7|07) software_install_custom ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}

software_bundle_menu() {
  clear_screen
  ui_panel_start "常用软件集合"
  ui_panel_line "集合会一次安装多个软件；如果只需要其中一个，请使用单项安装。"
  ui_panel_rule
  ui_panel_line "[01] 基础工具      [02] 现代 CLI"
  ui_panel_line "[03] 编译依赖      [04] 网络诊断"
  ui_panel_line "[05] 监控排障      [06] 备份同步"
  ui_panel_line "[07] 安全工具      [08] 代理常用依赖"
  ui_panel_line "[00] 返回"
  ui_panel_end
  printf '\n'
  local choice bundle=""
  choice="$(ask_input "请选择" "00")"
  case "$choice" in
    1|01) bundle="basic" ;;
    2|02) bundle="cli" ;;
    3|03) bundle="build" ;;
    4|04) bundle="network" ;;
    5|05) bundle="monitor" ;;
    6|06) bundle="backup" ;;
    7|07) bundle="security" ;;
    8|08) bundle="proxy" ;;
    0|00) return 0 ;;
    *) log_warn "未知选项：$choice"; return 1 ;;
  esac
  if ask_yes_no "确认安装整个 '$bundle' 集合？" "N"; then
    pkg_update_index
    if ! catalog_install_bundle "$bundle"; then
      log_warn "集合中有软件安装失败，其余已安装项目不会回滚。"
    fi
  fi
  return 0
}

software_install_basic() {
  log_step "安装基础工具"
  catalog_install_bundle basic || true
}

software_install_build_libs() {
  log_step "安装编译依赖与常用库"
  catalog_install_bundle build || true
}

software_install_proxy_deps() {
  log_step "安装代理节点常用依赖"
  catalog_install_bundle proxy || true
}

software_install_custom() {
  local input old_ifs arr=()
  input="$(ask_input "请输入要安装的软件包，多个包用空格分隔" "")"
  [[ -z "$input" ]] && return 0
  old_ifs="$IFS"
  IFS=' ' read -r -a arr <<< "$input"
  IFS="$old_ifs"
  pkg_update_index
  pkg_install "${arr[@]}"
}

software_runtime_menu() {
  while true; do
    clear_screen
    ui_panel_start "开发运行时"
    ui_panel_line "[01] 按单项选择运行时（推荐）"
    ui_panel_rule
    ui_panel_line "[02] Python 完整环境    [03] Node.js + npm"
    ui_panel_line "[04] Go                 [05] Rust + Cargo"
    ui_panel_line "[06] Java OpenJDK       [07] PHP + PHP-FPM"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) catalog_category_menu runtime ;;
      2|02) pkg_update_index; install_python_stack ;;
      3|03) pkg_update_index; install_node_stack ;;
      4|04) pkg_update_index; install_go_stack ;;
      5|05) pkg_update_index; install_rust_stack ;;
      6|06) pkg_update_index; install_java_stack ;;
      7|07) pkg_update_index; install_php_stack ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}

install_python_stack() {
  log_step "安装 Python 环境"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install python3 python3-pip python3-venv python3-dev pipx
  else
    pkg_install python3 python3-pip python3-devel python3-virtualenv pipx
  fi
}

install_node_stack() {
  log_step "从系统仓库安装 Node.js"
  pkg_install nodejs npm
}

install_go_stack() {
  log_step "从系统仓库安装 Go"
  [[ "$OS_FAMILY" == "debian" ]] && pkg_install golang-go || pkg_install golang
}

install_rust_stack() {
  log_step "从系统仓库安装 Rust"
  pkg_install rustc cargo
}

install_java_stack() {
  log_step "安装 OpenJDK"
  [[ "$OS_FAMILY" == "debian" ]] && pkg_install default-jdk || pkg_install_one_of java-latest-openjdk-devel java-openjdk-devel
}

install_php_stack() {
  log_step "安装 PHP-FPM"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install php php-cli php-fpm php-curl php-mbstring php-xml php-zip php-gd php-mysql php-pgsql php-sqlite3
  else
    pkg_install php php-cli php-fpm php-curl php-mbstring php-xml php-zip php-gd php-mysqlnd php-pgsql php-sqlite3
  fi
}
