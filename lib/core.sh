#!/usr/bin/env bash

TOOLKIT_NAME="Server Toolkit"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${SERVER_TOOLKIT_LOG_DIR:-/var/log/server-toolkit}"
BACKUP_ROOT="${SERVER_TOOLKIT_BACKUP_ROOT:-/var/backups/server-toolkit}"
LOG_FILE="${LOG_DIR}/serverctl-${RUN_ID}.log"
BACKUP_DIR="${BACKUP_ROOT}/${RUN_ID}"

ASSUME_YES=0
DRY_RUN=0
SKIP_UPDATE=0
UPGRADE_SYSTEM=0
NO_COLOR=0
OPT_ENABLE_BBR=0
OPT_NO_SSH=0
OPT_PROFILE=""
OPT_PURGE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

toolkit_parse_global_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) [[ -n "${2:-}" ]] || die "--profile requires a value"; OPT_PROFILE="$2"; shift 2 ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --skip-update) SKIP_UPDATE=1; shift ;;
      --upgrade) UPGRADE_SYSTEM=1; shift ;;
      --enable-bbr) OPT_ENABLE_BBR=1; shift ;;
      --no-ssh) OPT_NO_SSH=1; shift ;;
      --purge) OPT_PURGE=1; shift ;;
      --no-color) NO_COLOR=1; shift ;;
      -h|--help) shift ;;
      *) die "未知参数：$1" ;;
    esac
  done
  if [[ "$NO_COLOR" -eq 1 ]]; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
  fi
}

toolkit_init_runtime() {
  if [[ "${EUID}" -eq 0 ]]; then
    if ! mkdir -p "$LOG_DIR" "$BACKUP_DIR" 2>/dev/null; then
      LOG_DIR="/tmp/server-toolkit-logs"
      BACKUP_ROOT="/tmp/server-toolkit-backups"
      BACKUP_DIR="${BACKUP_ROOT}/${RUN_ID}"
      mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    fi
    LOG_FILE="${LOG_DIR}/serverctl-${RUN_ID}.log"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE" || true
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    LOG_FILE="/tmp/serverctl-${RUN_ID}.log"
    exec > >(tee -a "$LOG_FILE") 2>&1
  fi
  trap 'toolkit_on_error $LINENO' ERR
}

toolkit_on_error() {
  local line="$1"
  log_error "脚本在第 ${line} 行失败。"
  log_error "日志：${LOG_FILE}"
  [[ "${EUID}" -eq 0 ]] && log_error "备份：${BACKUP_DIR}"
}

log() {
  local level="$1"; shift
  local color="$NC"
  case "$level" in
    INFO) color="$GREEN" ;;
    WARN) color="$YELLOW" ;;
    ERROR) color="$RED" ;;
    STEP) color="$BLUE" ;;
    ASK) color="$CYAN" ;;
  esac
  printf '%b[%s]%b %s\n' "$color" "$level" "$NC" "$*"
}
log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_step() { log STEP "$@"; }

die() {
  log_error "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

path_is_safe_managed_target() {
  local path="${1:-}"
  [[ "$path" == /* ]] || return 1
  [[ "$path" != *'/../'* && "$path" != */.. && "$path" != *'/./'* && "$path" != */. ]] || return 1
  case "$path" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      return 1
      ;;
  esac
  # 至少包含两级路径，例如 /opt/server-toolkit。
  [[ "${path#/}" == */* ]]
}

valid_port() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))
}

require_root() {
  [[ "${EUID}" -eq 0 ]] && return 0
  if command_exists sudo; then
    log_warn "检测到非 root，尝试使用 sudo 重新运行。"
    exec sudo -E "$0" "${ORIGINAL_ARGS[@]}"
  fi
  die "请使用 root 运行。"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

safe_mkdir() {
  [[ "$DRY_RUN" -eq 1 ]] && { log_info "[DRY-RUN] mkdir -p $*"; return 0; }
  mkdir -p "$@"
}
