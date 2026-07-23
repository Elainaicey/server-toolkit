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

valid_port() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))
}

valid_port_range() {
  local value="${1:-}" start end
  if [[ "$value" =~ ^([0-9]+):([0-9]+)$ ]]; then
    start="${BASH_REMATCH[1]}"
    end="${BASH_REMATCH[2]}"
    valid_port "$start" && valid_port "$end" && (( 10#$start <= 10#$end ))
  else
    valid_port "$value"
  fi
}

valid_firewall_rule_spec() {
  local value="${1:-}" ports protocol="tcp"
  ports="$value"
  if [[ "$value" == */* ]]; then
    ports="${value%/*}"
    protocol="${value##*/}"
  fi
  valid_port_range "$ports" && [[ "$protocol" == "tcp" || "$protocol" == "udp" ]]
}

valid_ipv4_address() {
  local value="${1:-}" part
  local parts=()
  IFS='.' read -r -a parts <<<"$value"
  ((${#parts[@]} == 4)) || return 1
  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[0-9]{1,3}$ ]] && (( 10#$part <= 255 )) || return 1
  done
}

valid_firewall_source() {
  local value="${1:-}" address prefix=""
  [[ "$value" == "any" ]] && return 0
  address="$value"
  if [[ "$value" == */* ]]; then
    address="${value%/*}"
    prefix="${value##*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
  fi
  if valid_ipv4_address "$address"; then
    [[ -z "$prefix" ]] || (( 10#$prefix <= 32 ))
    return
  fi
  [[ "$address" == *:*:* && "$address" =~ ^[0-9a-fA-F:]+$ && "$address" != *:::* ]] || return 1
  [[ -z "$prefix" ]] || (( 10#$prefix <= 128 ))
}

valid_service_name() {
  [[ "${1:-}" =~ ^[a-zA-Z0-9@_.:-]+$ ]]
}

valid_username() {
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_pid() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] && (( 10#$pid >= 2 && 10#$pid <= 4194304 ))
}

valid_nice_value() {
  local value="${1:-}" magnitude numeric
  [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
  if [[ "$value" == -* ]]; then
    magnitude="${value#-}"
    numeric=$((-10#$magnitude))
  else
    numeric=$((10#$value))
  fi
  (( numeric >= -20 && numeric <= 19 ))
}

valid_ssh_public_key() {
  local value="${1:-}" key_type key_data remainder
  [[ -n "$value" && "$value" != *[[:cntrl:]]* ]] || return 1
  IFS=' ' read -r key_type key_data remainder <<<"$value"
  case "$key_type" in
    ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|\
      sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
    *) return 1 ;;
  esac
  [[ "${#key_data}" -ge 40 && "$key_data" =~ ^[A-Za-z0-9+/]+={0,3}$ ]]
}

valid_network_target() {
  local target="${1:-}"
  [[ "$target" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,252}$ || "$target" =~ ^[a-fA-F0-9:]+$ ]]
}

safe_managed_path() {
  local path="${1:-}"
  [[ "$path" == /* ]] || return 1
  [[ "$path" != *'/../'* && "$path" != */.. && "$path" != *'/./'* && "$path" != */. ]] || return 1
  case "$path" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var) return 1 ;;
  esac
  [[ "${path#/}" == */* ]]
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
