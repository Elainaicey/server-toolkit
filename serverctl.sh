#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'

SERVERCTL_VERSION="0.3.0"
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

全局选项：
  --profile NAME        minimal/proxy/docker/web/dev/full
  --yes, -y             自动确认，适合无人值守
  --dry-run             只打印将执行的动作，不真正修改系统
  --skip-update         跳过软件源刷新
  --upgrade             基础初始化时升级已安装软件包
  --enable-bbr          执行 profile 时强制启用 BBR
  --no-ssh              执行 profile 时跳过 SSH 修改
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

print_home_dashboard() {
  local os_line="${OS_ID:-unknown} ${OS_VERSION_ID:-}"
  local virt_line="${ARCH:-unknown} / ${VIRT:-unknown}"
  local memory_line="${MEM_TOTAL_MB:-?} MB / Swap ${SWAP_TOTAL_MB:-?} MB"
  local network_line="IPv4 $(status_word "${HAS_IPV4:-0}") / IPv6 $(status_word "${HAS_IPV6:-0}") / GitHub $(status_word "${GITHUB_OK:-0}")"
  local security_line="SSH ${SSH_PORT:-?} / 防火墙 $(ui_short "${FIREWALL_STATE:-未知}" 24)"
  local port_line="80 ${PORT_80:-空闲} / 443 ${PORT_443:-空闲}"

  print_section "当前环境"
  printf '  %b系统%b  %s\n' "$DIM" "$NC" "$os_line"
  printf '  %b平台%b  %s\n' "$DIM" "$NC" "$virt_line"
  printf '  %b资源%b  CPU %s 核 / %s\n' "$DIM" "$NC" "${CPU_CORES:-?}" "$memory_line"
  printf '  %b网络%b  %s\n' "$DIM" "$NC" "$network_line"
  printf '  %b安全%b  %s\n' "$DIM" "$NC" "$security_line"
  printf '  %b端口%b  %s\n' "$DIM" "$NC" "$port_line"
  printf '\n'
}

print_home_menu() {
  print_section "功能入口"
  printf '  %b基础与系统%b\n' "$CYAN" "$NC"
  printf '    [1] 系统总览与建议        [2] 快速初始化\n'
  printf '    [3] 系统设置中心          [4] 软件安装中心\n\n'
  printf '  %b网络与安全%b\n' "$CYAN" "$NC"
  printf '    [5] 网络优化 / IPv6 / BBR [6] SSH 与登录安全\n'
  printf '    [7] 防火墙与端口          [12] 系统修复与回滚\n\n'
  printf '  %b服务与运行时%b\n' "$CYAN" "$NC"
  printf '    [8] 容器与 Docker         [9] Web 服务\n'
  printf '    [10] 数据库 / 缓存        [11] 监控 / 排障 / 备份工具\n\n'
  printf '  %b报告%b\n' "$CYAN" "$NC"
  printf '    [13] 生成系统报告         [0] 退出\n\n'
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
    choice="$(ask_input "请输入编号" "1")"
    case "$choice" in
      1) print_detection_summary; pause ;;
      2) base_menu ;;
      3) system_settings_menu ;;
      4) software_center_menu ;;
      5) network_menu ;;
      6) ssh_menu ;;
      7) firewall_menu ;;
      8) docker_menu ;;
      9) web_menu ;;
      10) database_menu ;;
      11) tools_menu ;;
      12) maintenance_menu ;;
      13) generate_report; pause ;;
      0) exit 0 ;;
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
      --yes|-y|--dry-run|--skip-update|--upgrade|--enable-bbr|--no-ssh|--no-color)
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
    *) die "未知命令：$cmd" ;;
  esac
}

main "$@"
