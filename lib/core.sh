#!/usr/bin/env bash

DRY_RUN=0
NO_COLOR=0
RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''

setup_colors() {
  if [[ "$NO_COLOR" -eq 1 || ! -t 1 ]]; then
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
  else
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
  fi
}

info() { printf '%b[信息]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[提醒]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
error() { printf '%b[错误]%b %s\n' "$RED" "$NC" "$*" >&2; }
die() { error "$*"; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "此操作需要 root 权限，请使用 sudo serverctl。"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%b[预览]%b' "$CYAN" "$NC"
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

read_input() {
  local prompt="$1"
  local default_value="${2:-}"
  local answer=""
  local label="$prompt"
  [[ -n "$default_value" ]] && label+=" [$default_value]"
  label+=": "

  if [[ -t 0 ]]; then
    read -r -p "$label" answer || true
  elif [[ -r /dev/tty ]]; then
    read -r -p "$label" answer </dev/tty || true
  fi
  printf '%s' "${answer:-$default_value}"
}

confirm() {
  local question="$1"
  local answer
  answer="$(read_input "$question [y/N]" "")"
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

pause() {
  [[ -t 0 || -r /dev/tty ]] || return 0
  read_input "按 Enter 返回" "" >/dev/null
}

valid_port() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))
}

safe_managed_path() {
  local path="${1:-}"
  [[ "$path" == /* ]] || return 1
  [[ "$path" != *'/../'* && "$path" != */.. && "$path" != *'/./'* && "$path" != */. ]] || return 1
  case "$path" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      return 1
      ;;
  esac
  [[ "${path#/}" == */* ]]
}
