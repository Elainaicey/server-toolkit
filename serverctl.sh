#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'

SERVERCTL_VERSION="0.1.0"
SOURCE_FILE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_FILE" ]]; do
  SOURCE_DIR="$(cd -P -- "$(dirname -- "$SOURCE_FILE")" >/dev/null 2>&1 && pwd)"
  SOURCE_FILE="$(readlink "$SOURCE_FILE")"
  [[ "$SOURCE_FILE" == /* ]] || SOURCE_FILE="$SOURCE_DIR/$SOURCE_FILE"
done
ROOT_DIR="${SERVER_TOOLKIT_ROOT:-$(cd -P -- "$(dirname -- "$SOURCE_FILE")" >/dev/null 2>&1 && pwd)}"

# shellcheck source=lib/core.sh
. "$ROOT_DIR/lib/core.sh"
. "$ROOT_DIR/lib/ui.sh"
. "$ROOT_DIR/lib/platform.sh"
. "$ROOT_DIR/lib/backup.sh"
. "$ROOT_DIR/lib/catalog.sh"
. "$ROOT_DIR/features/software.sh"
. "$ROOT_DIR/features/system.sh"
. "$ROOT_DIR/features/network.sh"
. "$ROOT_DIR/features/security.sh"

usage() {
  cat <<'EOF'
Server Toolkit 0.1.0

用法：
  serverctl                     打开交互界面
  serverctl doctor              检查运行环境
  serverctl list [关键词]       查看单项软件目录
  serverctl install ID          安装一个软件项
  serverctl version             显示版本

选项：
  --dry-run                     预览命令，不修改系统
  --no-color                    禁用颜色
  -h, --help                    显示帮助

每次 install 只接受一个软件 ID，并且安装前必须人工确认。
EOF
}

main_menu() {
  platform_detect
  while true; do
    ui_banner
    printf '%s · %s · %s MB 内存 · %s MB Swap\n\n' "$OS_NAME" "$ARCH" "$MEMORY_MB" "$SWAP_MB"
    ui_item 01 "系统概览"
    ui_item 02 "环境检查"
    ui_item 03 "安装一个软件" "支持搜索，不提供批量安装"
    ui_item 04 "修改主机名"
    ui_item 05 "修改时区"
    ui_item 06 "创建 Swap"
    ui_item 07 "查看网络信息"
    ui_item 08 "启用 BBR"
    ui_item 09 "设置 IP 地址优先级"
    ui_item 10 "启用基础防火墙"
    ui_item 11 "配置 SSH 安全"
    ui_item 00 "退出"
    printf '\n%b修改系统的动作都会显示摘要并再次确认。%b\n' "$DIM" "$NC"

    local choice
    choice="$(read_input "请选择" "01")"
    case "$choice" in
      1|01) system_overview; pause ;;
      2|02) system_doctor; pause ;;
      3|03) software_catalog_menu ;;
      4|04) system_set_hostname || true; pause ;;
      5|05) system_set_timezone || true; pause ;;
      6|06) system_create_swap || true; pause ;;
      7|07) network_show; pause ;;
      8|08) network_enable_bbr || true; pause ;;
      9|09) network_set_address_preference || true; pause ;;
      10) security_enable_firewall || true; pause ;;
      11) security_configure_ssh || true; pause ;;
      0|00) return 0 ;;
      *) warn "未知选项：$choice"; pause ;;
    esac
  done
}

main() {
  local command="menu"
  local command_set=0
  local arguments=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --no-color) NO_COLOR=1 ;;
      -h|--help|help) setup_colors; usage; return 0 ;;
      --*) die "未知选项：$1" ;;
      *)
        if [[ "$command_set" -eq 0 ]]; then
          command="$1"
          command_set=1
        else
          arguments+=("$1")
        fi
        ;;
    esac
    shift
  done
  setup_colors

  case "$command" in
    menu)
      ((${#arguments[@]} == 0)) || die "menu 不接受参数。"
      main_menu
      ;;
    doctor)
      ((${#arguments[@]} == 0)) || die "doctor 不接受参数。"
      system_doctor
      ;;
    list)
      ((${#arguments[@]} <= 1)) || die "list 最多接受一个关键词。"
      platform_detect
      catalog_print "${arguments[0]:-}"
      ;;
    install)
      ((${#arguments[@]} == 1)) || die "用法：serverctl install ID（一次只能安装一个软件）"
      platform_detect
      catalog_install "${arguments[0]}"
      ;;
    version)
      ((${#arguments[@]} == 0)) || die "version 不接受参数。"
      printf 'Server Toolkit %s\n' "$SERVERCTL_VERSION"
      ;;
    *) die "未知命令：$command" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
