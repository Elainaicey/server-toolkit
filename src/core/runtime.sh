#!/usr/bin/env bash

# 颜色变量由随后加载的 UI 与 feature 模块消费。
# shellcheck disable=SC2034

DRY_RUN=0
NO_COLOR=0
RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; WHITE=''; MUTED=''; BOLD=''; NC=''
AUDIT_LOG="${SERVER_TOOLKIT_AUDIT_LOG:-/var/log/server-toolkit/actions.log}"
STATE_ROOT="${SERVER_TOOLKIT_STATE_ROOT:-/var/lib/server-toolkit}"

runtime_colors() {
  if [[ "$NO_COLOR" -eq 1 || ! -t 1 ]]; then
    return 0
  fi
  # 使用明亮的 ANSI 基础色，兼顾深色终端、低色彩终端和 SSH 会话。
  RED=$'\033[0;91m'; GREEN=$'\033[0;92m'; YELLOW=$'\033[0;93m'
  BLUE=$'\033[0;94m'; MAGENTA=$'\033[0;95m'; CYAN=$'\033[0;96m'
  WHITE=$'\033[0;97m'; MUTED=$'\033[0;90m'; BOLD=$'\033[1m'; NC=$'\033[0m'
}

info() { printf '%b[信息]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[提醒]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
error() { printf '%b[错误]%b %s\n' "$RED" "$NC" "$*" >&2; }
die() { error "$*"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }
require_root() { [[ "${EUID}" -eq 0 ]] || die "此操作需要 root 权限，请使用 sudo serverctl。"; }

terminal_safe_text() {
  local value="${1:-}"
  value="${value//[[:cntrl:]]/ }"
  printf '%s' "$value"
}

runtime_locale() {
  local charmap fallback
  charmap="$(locale charmap 2>/dev/null || true)"
  if [[ "$charmap" != "UTF-8" ]]; then
    fallback="$(locale -a 2>/dev/null | awk 'tolower($0)=="c.utf8" || tolower($0)=="c.utf-8" {print; exit}')"
    if [[ -n "$fallback" ]]; then export LC_ALL="$fallback"; fi
  fi
}

audit() {
  local message="$*"
  [[ "${EUID}" -eq 0 && "$DRY_RUN" -eq 0 ]] || return 0
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  printf '%s user=%s pid=%s %s\n' "$(date -Is)" "${SUDO_USER:-root}" "$$" "$message" >>"$AUDIT_LOG" 2>/dev/null || true
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%b[预览]%b' "$BLUE" "$NC"
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

read_input() {
  local prompt default_value answer label
  prompt="$1"
  default_value="${2:-}"
  answer=""
  label="$prompt"
  [[ -n "$default_value" ]] && label+=" [$default_value]"
  label+=": "
  if [[ -t 0 ]]; then
    read -r -p "$label" answer || true
  elif [[ -t 2 && -r /dev/tty ]]; then
    read -r -p "$label" answer </dev/tty || true
  fi
  printf '%s' "${answer:-$default_value}"
}

confirm() {
  local answer
  answer="$(read_input "$1 [y/N]" "")"
  case "$answer" in y|Y|yes|YES|Yes|是|确认) return 0 ;; *) return 1 ;; esac
}

pause() {
  [[ -t 0 || -r /dev/tty ]] || return 0
  read_input "按 Enter 返回" "" >/dev/null
}

runtime_error() {
  local line="$1" command="$2" status="$3"
  error "操作失败（状态 $status，行 $line）：$command"
  audit "result=failed status=$status line=$line command=$(printf '%q' "$command")"
}

runtime_init() {
  runtime_locale
  runtime_colors
  trap 'status=$?; runtime_error "$LINENO" "$BASH_COMMAND" "$status"' ERR
}
