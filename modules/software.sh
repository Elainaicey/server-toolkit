#!/usr/bin/env bash

software_center_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    ui_panel_start "软件安装中心"
    ui_panel_line "[01] 基础工具        curl/wget/git/jq/vim/unzip/tmux"
    ui_panel_line "[02] 现代 CLI        ripgrep/fd/bat/fzf/tree/neovim"
    ui_panel_line "[03] 编译依赖/库     gcc/make/cmake/pkg-config/ssl/ffi/zlib"
    ui_panel_line "[04] 开发运行时      Python/Node.js/Go/Rust/Java/PHP"
    ui_panel_rule
    ui_panel_line "[05] 容器环境        Docker/Compose"
    ui_panel_line "[06] Web 环境        Caddy/Nginx/Certbot"
    ui_panel_line "[07] 数据库/缓存     Redis/PostgreSQL/MariaDB/SQLite"
    ui_panel_line "[08] 监控排障        sysstat/iotop/iftop/ncdu/tcpdump"
    ui_panel_rule
    ui_panel_line "[09] 备份同步        rclone/restic/borgbackup/rsync"
    ui_panel_line "[10] 安全工具        fail2ban/防火墙/openssl"
    ui_panel_line "[11] 代理节点依赖    socat/cron/iptables/nftables/qrencode"
    ui_panel_line "[12] 自定义包名安装"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择分类" "00")"
    case "$choice" in
      1|01) pkg_update_index; software_install_basic ;;
      2|02) pkg_update_index; tools_install_modern_cli ;;
      3|03) pkg_update_index; software_install_build_libs ;;
      4|04) software_runtime_menu ;;
      5|05) docker_menu ;;
      6|06) web_menu ;;
      7|07) database_menu ;;
      8|08) pkg_update_index; monitor_install_tools ;;
      9|09) pkg_update_index; tools_install_backup_tools ;;
      10) pkg_update_index; tools_install_security_tools ;;
      11) pkg_update_index; software_install_proxy_deps ;;
      12) software_install_custom ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}

software_install_basic() {
  log_step "安装基础工具"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install curl wget git jq vim unzip zip tar gzip xz-utils htop tmux lsof psmisc net-tools iproute2 dnsutils sudo bash-completion gnupg rsync
  else
    pkg_install curl wget git jq vim-enhanced unzip zip tar gzip xz htop tmux lsof psmisc net-tools iproute bind-utils sudo bash-completion gnupg2 rsync
  fi
}

software_install_build_libs() {
  log_step "安装编译依赖与常用库"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install build-essential make gcc g++ pkg-config autoconf automake libtool cmake ninja-build libssl-dev libffi-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev
  else
    pkg_install gcc gcc-c++ make pkgconf-pkg-config autoconf automake libtool cmake ninja-build openssl-devel libffi-devel zlib-devel bzip2-devel readline-devel sqlite-devel xz-devel
  fi
}

software_install_proxy_deps() {
  log_step "安装代理节点常用依赖"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install curl wget socat cron openssl ca-certificates iptables nftables qrencode unzip tar gzip jq
  else
    pkg_install curl wget socat cronie openssl ca-certificates iptables nftables qrencode unzip tar gzip jq
  fi
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
    ui_panel_line "[01] Python 3 / pip / venv / pipx"
    ui_panel_line "[02] Node.js / npm"
    ui_panel_line "[03] Go"
    ui_panel_line "[04] Rust / Cargo"
    ui_panel_line "[05] Java OpenJDK"
    ui_panel_line "[06] PHP-FPM"
    ui_panel_rule
    ui_panel_line "[07] 全部安装"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) pkg_update_index; install_python_stack ;;
      2|02) pkg_update_index; install_node_stack ;;
      3|03) pkg_update_index; install_go_stack ;;
      4|04) pkg_update_index; install_rust_stack ;;
      5|05) pkg_update_index; install_java_stack ;;
      6|06) pkg_update_index; install_php_stack ;;
      7|07)
        pkg_update_index
        install_python_stack
        install_node_stack
        install_go_stack
        install_rust_stack
        install_java_stack
        install_php_stack
        ;;
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
