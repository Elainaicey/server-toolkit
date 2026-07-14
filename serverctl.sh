#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'

SERVERCTL_VERSION="0.1.0"
SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  SOURCE_DIR="$(cd -P -- "$(dirname -- "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="${SOURCE_DIR}/${SOURCE_PATH}"
done
SCRIPT_PATH="$(cd -P -- "$(dirname -- "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="${SERVER_TOOLKIT_ROOT:-$SCRIPT_PATH}"
ORIGINAL_ARGS=("$@")

# shellcheck source=lib/core.sh
. "$ROOT_DIR/lib/core.sh"
. "$ROOT_DIR/lib/ui.sh"
. "$ROOT_DIR/lib/backup.sh"
. "$ROOT_DIR/lib/detect.sh"
. "$ROOT_DIR/lib/package.sh"

for module in "$ROOT_DIR"/modules/*.sh; do
  # shellcheck source=/dev/null
  . "$module"
done

usage() {
  cat <<USAGE
Server Toolkit v${SERVERCTL_VERSION}

用法：
  serverctl                         打开中文交互菜单
  serverctl menu                    打开中文交互菜单
  serverctl detect                  系统检测
  serverctl report                  生成 /root/server-report.txt
  serverctl install --profile NAME  执行无人值守 profile
  serverctl base                    基础初始化
  serverctl system                  系统设置中心
  serverctl network                 网络 / IPv6 / BBR
  serverctl ssh                     SSH 安全配置
  serverctl docker                  Docker 环境
  serverctl web                     Web 环境
  serverctl database                数据库
  serverctl monitor                 监控与排障工具
  serverctl tools                   工具中心
  serverctl repair                  系统修复
  serverctl rollback                回滚备份
  serverctl maintenance             系统修复与回滚聚合入口
  serverctl uninstall               卸载 Server Toolkit

全局选项：
  --profile NAME        minimal/proxy/docker/web/dev/full
  --yes, -y             自动确认，适合无人值守
  --dry-run             只打印将执行的动作，不真正修改系统
  --skip-update         跳过软件源刷新
  --upgrade             基础初始化时升级已安装软件包
  --enable-bbr          执行 profile 时强制启用 BBR
  --no-ssh              执行 profile 时跳过 SSH 修改
  --purge               卸载时同时删除日志和备份
  --no-color            禁用彩色输出
  -h, --help            查看帮助

说明：
  serverctl install --profile proxy 是无人值守模式，会直接按 profile 执行。
  如果你想要交互选择安装内容，请运行 serverctl 或 serverctl menu。

远程安装示例：
  curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh -o /tmp/install.sh
  bash -n /tmp/install.sh
  sudo bash /tmp/install.sh
USAGE
}

load_profile() {
  local name="$1"
  local file="$ROOT_DIR/profiles/${name}.conf"
  [[ -f "$file" ]] || die "未找到 profile：$name"
  # shellcheck source=/dev/null
  . "$file"
  PROFILE_NAME="$name"
}

apply_profile_overrides() {
  [[ "${OPT_ENABLE_BBR:-0}" -eq 1 ]] && PROFILE_ENABLE_BBR=1
  [[ "${OPT_NO_SSH:-0}" -eq 1 ]] && PROFILE_SSH_HARDEN=0
  return 0
}

run_profile() {
  require_root
  [[ -n "${PROFILE_NAME:-}" ]] || die "缺少 --profile NAME"
  detect_system
  print_detection_summary
  apply_profile_overrides

  if ! ask_yes_no "是否立即执行 profile '${PROFILE_NAME}'？这会按预设安装/配置相关项目" "Y"; then
    log_warn "已取消。"
    return 0
  fi

  pkg_update_index
  [[ "${PROFILE_UPGRADE_SYSTEM:-0}" -eq 1 ]] && pkg_upgrade_system
  base_install_core
  [[ -n "${PROFILE_HOSTNAME:-}" ]] && system_set_hostname "$PROFILE_HOSTNAME"
  [[ "${PROFILE_AUTO_UPDATES:-0}" -eq 1 ]] && base_enable_auto_updates
  [[ -n "${PROFILE_TIMEZONE:-}" ]] && base_set_timezone "$PROFILE_TIMEZONE"
  [[ -n "${PROFILE_LOCALE:-}" ]] && system_set_locale "$PROFILE_LOCALE"
  [[ "${PROFILE_FIX_HOSTS:-1}" -eq 1 ]] && base_fix_hosts_resolution

  if [[ "${PROFILE_ENABLE_BBR:-0}" -eq 1 ]]; then
    network_enable_bbr
  fi
  if [[ -n "${PROFILE_IP_PREFERENCE:-}" ]]; then
    network_set_ip_preference "$PROFILE_IP_PREFERENCE"
  fi
  if [[ -n "${PROFILE_TCP_PROFILE:-}" ]]; then
    network_apply_tcp_profile "$PROFILE_TCP_PROFILE"
  fi

  if [[ "${PROFILE_SSH_HARDEN:-0}" -eq 1 ]]; then
    ssh_apply_profile_hardening "${PROFILE_SSH_PORT:-}" "${PROFILE_DISABLE_PASSWORD:-0}" "${PROFILE_DISABLE_ROOT:-0}"
  fi

  if [[ "${PROFILE_FIREWALL:-0}" -eq 1 ]]; then
    firewall_enable_basic "${PROFILE_OPEN_PORTS:-}"
  fi

  if [[ -n "${PROFILE_PACKAGES:-}" ]]; then
    local profile_pkgs=()
    local old_ifs="$IFS"
    IFS=' ' read -r -a profile_pkgs <<< "$PROFILE_PACKAGES"
    IFS="$old_ifs"
    pkg_install "${profile_pkgs[@]}"
  fi

  local profile_modules=()
  local old_ifs="$IFS"
  IFS=' ' read -r -a profile_modules <<< "${PROFILE_MODULES:-}"
  IFS="$old_ifs"
  local item
  for item in "${profile_modules[@]}"; do
    [[ -z "$item" ]] && continue
    case "$item" in
      docker) docker_install_official ;;
      web) web_install_stack "${PROFILE_WEB_STACK:-caddy}" ;;
      database) database_install_from_profile "${PROFILE_DATABASES:-}" ;;
      monitor) monitor_install_tools ;;
      *) log_warn "未知 profile 模块：$item" ;;
    esac
  done

  pkg_cleanup
  log_info "配置档 '${PROFILE_NAME}' 执行完成。"
}

status_word() {
  local value="${1:-0}"
  if [[ "$value" -eq 1 ]]; then
    printf '可用'
  else
    printf '不可用'
  fi
}

status_badge() {
  local value="${1:-0}"
  if [[ "$value" -eq 1 ]]; then
    ui_badge "可用" "$GREEN"
  else
    ui_badge "异常" "$YELLOW"
  fi
}

apt_badge() {
  if [[ -n "${APT_ISSUES:-}" ]]; then
    ui_badge "需修复" "$YELLOW"
  else
    ui_badge "正常" "$GREEN"
  fi
}

print_home_dashboard() {
  local os_line="${OS_ID:-unknown} ${OS_VERSION_ID:-}"
  local virt_line="${ARCH:-unknown} / ${VIRT:-unknown}"
  local memory_line="CPU ${CPU_CORES:-?} 核 / ${MEM_TOTAL_MB:-?} MB / Swap ${SWAP_TOTAL_MB:-?} MB"
  local network_line="$(status_badge "${HAS_IPV4:-0}") IPv4  $(status_badge "${HAS_IPV6:-0}") IPv6  $(status_badge "${GITHUB_OK:-0}") GitHub"
  local security_line="SSH ${SSH_PORT:-?} / 防火墙 $(ui_short "${FIREWALL_STATE:-未知}" 24)"
  local port_line="80 ${PORT_80:-空闲} / 443 ${PORT_443:-空闲}"

  ui_panel_start "当前环境"
  ui_panel_line "$(printf '%b系统%b  %-20s  %b平台%b  %s' "$DIM" "$NC" "$os_line" "$DIM" "$NC" "$virt_line")"
  ui_panel_line "$(printf '%b资源%b  %s' "$DIM" "$NC" "$memory_line")"
  ui_panel_line "$(printf '%b网络%b  %b' "$DIM" "$NC" "$network_line")"
  ui_panel_line "$(printf '%b包管理%b  %s APT / %s' "$DIM" "$NC" "$(apt_badge)" "${PM:-未知}")"
  ui_panel_line "$(printf '%b安全%b  %s' "$DIM" "$NC" "$security_line")"
  ui_panel_line "$(printf '%b端口%b  %s' "$DIM" "$NC" "$port_line")"
  ui_panel_end
  printf '\n'
}

print_home_menu() {
  ui_panel_start "功能入口"
  ui_panel_line "$(printf '%b基础与系统%b' "$CYAN" "$NC")"
  ui_panel_line "  [01] 系统总览与建议      [02] 快速初始化"
  ui_panel_line "  [03] 系统设置中心        [04] 软件安装中心"
  ui_panel_rule
  ui_panel_line "$(printf '%b网络与安全%b' "$CYAN" "$NC")"
  ui_panel_line "  [05] 网络优化 / BBR      [06] SSH 与登录安全"
  ui_panel_line "  [07] 防火墙与端口        [12] 系统修复与回滚"
  ui_panel_rule
  ui_panel_line "$(printf '%b服务与运行时%b' "$CYAN" "$NC")"
  ui_panel_line "  [08] 容器与 Docker       [09] Web 服务"
  ui_panel_line "  [10] 数据库 / 缓存       [11] 监控 / 排障 / 备份"
  ui_panel_rule
  ui_panel_line "$(printf '%b管理%b' "$CYAN" "$NC")"
  ui_panel_line "  [13] 生成系统报告        [14] 卸载 Server Toolkit"
  ui_panel_line "  [00] 退出"
  ui_panel_end
  printf '\n'
}

uninstall_toolkit() {
  require_root
  local install_dir="$ROOT_DIR"
  local command_path="/usr/local/bin/serverctl"
  local resolved_command=""
  local resolved_script="$SCRIPT_PATH/serverctl.sh"
  local scope="core"
  local choice=""

  if command -v serverctl >/dev/null 2>&1; then
    command_path="$(command -v serverctl)"
  fi
  resolved_command="$(readlink -f "$command_path" 2>/dev/null || true)"

  ui_panel_start "卸载 Server Toolkit"
  ui_panel_line "$(printf '%b命令入口%b  %s' "$DIM" "$NC" "$command_path")"
  ui_panel_line "$(printf '%b安装目录%b  %s' "$DIM" "$NC" "$install_dir")"
  ui_panel_line "$(printf '%b日志目录%b  %s' "$DIM" "$NC" "$LOG_DIR")"
  ui_panel_line "$(printf '%b备份目录%b  %s' "$DIM" "$NC" "$BACKUP_ROOT")"
  ui_panel_end
  printf '\n'

  if [[ "$OPT_PURGE" -eq 1 ]]; then
    scope="all"
    log_warn "已启用 --purge：将删除入口、安装目录、日志和备份。"
  elif [[ "$ASSUME_YES" -eq 1 ]]; then
    scope="core"
  else
    ui_panel_start "请选择卸载范围"
    ui_panel_line "[1] 仅删除命令入口"
    ui_panel_line "[2] 删除命令入口 + 安装目录（推荐）"
    ui_panel_line "[3] 删除命令入口 + 安装目录 + 日志"
    ui_panel_line "[4] 全部删除：入口 + 安装目录 + 日志 + 备份"
    ui_panel_line "[0] 取消"
    ui_panel_end
    printf '\n'
    choice="$(ask_choice "请选择" "2" "0 1 2 3 4")"
    case "$choice" in
      0) log_warn "已取消卸载。"; return 0 ;;
      1) scope="entry" ;;
      2) scope="core" ;;
      3) scope="logs" ;;
      4) scope="all" ;;
    esac
  fi

  if [[ "$ASSUME_YES" -ne 1 ]] && ! ask_yes_no "确认卸载 Server Toolkit？" "N"; then
    log_warn "已取消卸载。"
    return 0
  fi

  if [[ -e "$command_path" || -L "$command_path" ]]; then
    if [[ -z "$resolved_command" || "$resolved_command" == "$resolved_script" || "$resolved_command" == "$install_dir/serverctl.sh" ]]; then
      run rm -f "$command_path"
      [[ "$DRY_RUN" -eq 1 ]] && log_info "将删除命令入口：$command_path" || log_info "已删除命令入口：$command_path"
    else
      log_warn "命令入口不指向当前安装目录，已跳过：$command_path -> $resolved_command"
    fi
  fi

  if [[ "$scope" != "entry" && -d "$install_dir" ]]; then
    run rm -rf "$install_dir"
    [[ "$DRY_RUN" -eq 1 ]] && log_info "将删除安装目录：$install_dir" || log_info "已删除安装目录：$install_dir"
  fi

  if [[ "$scope" == "logs" || "$scope" == "all" ]]; then
    [[ -d "$LOG_DIR" ]] && run rm -rf "$LOG_DIR"
    [[ "$DRY_RUN" -eq 1 ]] && log_info "将删除日志目录：$LOG_DIR" || log_info "已删除日志目录：$LOG_DIR"
  fi

  if [[ "$scope" == "all" ]]; then
    [[ -d "$BACKUP_ROOT" ]] && run rm -rf "$BACKUP_ROOT"
    [[ "$DRY_RUN" -eq 1 ]] && log_info "将删除备份目录：$BACKUP_ROOT" || log_info "已删除备份目录：$BACKUP_ROOT"
  fi

  case "$scope" in
    entry) log_info "安装目录、日志与备份已保留。" ;;
    core) log_info "日志与备份已保留：$LOG_DIR / $BACKUP_ROOT" ;;
    logs) log_info "备份已保留：$BACKUP_ROOT" ;;
  esac
}

interactive_menu() {
  detect_system || true
  while true; do
    clear_screen
    print_main_banner "$SERVERCTL_VERSION"
    print_home_dashboard
    print_menu_hint
    print_home_menu
    local choice
    choice="$(ask_input "请输入编号" "01")"
    case "$choice" in
      1|01) print_detection_summary; pause ;;
      2|02) base_menu ;;
      3|03) system_settings_menu ;;
      4|04) software_center_menu ;;
      5|05) network_menu ;;
      6|06) ssh_menu ;;
      7|07) firewall_menu ;;
      8|08) docker_menu ;;
      9|09) web_menu ;;
      10) database_menu ;;
      11) tools_menu ;;
      12) maintenance_menu ;;
      13) generate_report; pause ;;
      14) uninstall_toolkit; exit 0 ;;
      0|00) exit 0 ;;
      *) log_warn "未知选项：$choice"; pause ;;
    esac
  done
}

main() {
  local cmd="menu"
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
      --profile)
        [[ -n "${2:-}" ]] || die "--profile requires a value"
        args+=("$1" "$2")
        shift 2
        ;;
      --yes|-y|--dry-run|--skip-update|--upgrade|--enable-bbr|--no-ssh|--purge|--no-color)
        args+=("$1")
        shift
        ;;
      --*)
        args+=("$1")
        shift
        ;;
      *)
        cmd="$1"
        shift
        args+=("$@")
        break
        ;;
    esac
  done

  toolkit_parse_global_args "${args[@]}"
  toolkit_init_runtime

  case "$cmd" in
    -h|--help|help) usage ;;
    menu) interactive_menu ;;
    detect) detect_system; print_detection_summary ;;
    report) require_root; detect_system; generate_report ;;
    install)
      [[ -n "${OPT_PROFILE:-}" ]] || die "用法：serverctl install --profile NAME"
      load_profile "$OPT_PROFILE"
      run_profile
      ;;
    base) require_root; detect_system; base_menu ;;
    system) require_root; detect_system; system_settings_menu ;;
    network) require_root; detect_system; network_menu ;;
    ssh) require_root; detect_system; ssh_menu ;;
    docker) require_root; detect_system; docker_menu ;;
    web) require_root; detect_system; web_menu ;;
    database) require_root; detect_system; database_menu ;;
    monitor) require_root; detect_system; monitor_menu ;;
    repair) require_root; detect_system; repair_menu ;;
    rollback) require_root; rollback_menu ;;
    tools) require_root; detect_system; tools_menu ;;
    maintenance) require_root; detect_system; maintenance_menu ;;
    uninstall) uninstall_toolkit ;;
    *) die "未知命令：$cmd" ;;
  esac
}

main "$@"
