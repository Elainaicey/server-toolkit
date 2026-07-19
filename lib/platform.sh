#!/usr/bin/env bash

OS_ID=""
OS_VERSION=""
OS_NAME=""
OS_CODENAME=""
ARCH=""
CPU_CORES=""
MEMORY_MB=""
SWAP_MB=""
ROOT_USAGE=""
VIRTUALIZATION=""
PACKAGE_INDEX_UPDATED=0

platform_detect() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck source=/dev/null
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_NAME="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  case "$OS_ID" in
    debian|ubuntu) ;;
    *) die "当前仅支持 Debian 和 Ubuntu，检测到：$OS_NAME" ;;
  esac
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  CPU_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '?')"
  MEMORY_MB="$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || printf '?')"
  SWAP_MB="$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || printf '0')"
  ROOT_USAGE="$(df -h / 2>/dev/null | awk 'NR == 2 {print $3 "/" $2 " (" $5 ")"}')"
  VIRTUALIZATION="$(systemd-detect-virt 2>/dev/null || printf 'unknown')"
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

package_wait_for_lock() {
  command_exists fuser || return 0
  local waited=0
  local locks=(/var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock)
  while fuser "${locks[@]}" >/dev/null 2>&1; do
    (( waited == 0 )) && info "APT 正被其他进程使用，等待锁释放……"
    (( waited >= 180 )) && die "等待 APT 锁超过 180 秒，请稍后重试。"
    sleep 3
    waited=$((waited + 3))
  done
}

apt_run() {
  package_wait_for_lock
  run env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -o Acquire::Retries=3 \
    "$@"
}

package_update_index() {
  [[ "$PACKAGE_INDEX_UPDATED" -eq 1 ]] && return 0
  info "刷新软件索引……"
  apt_run update
  PACKAGE_INDEX_UPDATED=1
}

package_invalidate_index() {
  PACKAGE_INDEX_UPDATED=0
}

package_install() {
  local requested=("$@")
  local missing=()
  local package
  for package in "${requested[@]}"; do
    [[ -n "$package" ]] || continue
    package_installed "$package" || missing+=("$package")
  done
  if ((${#missing[@]} == 0)); then
    info "已经安装，无需操作。"
    return 0
  fi
  package_update_index
  local display=""
  printf -v display '%s ' "${missing[@]}"
  info "将安装系统包：${display% }"
  apt_run install -y "${missing[@]}"
}

service_exists() {
  local service="$1"
  command_exists systemctl || return 1
  systemctl list-unit-files --type=service --no-legend "$service" 2>/dev/null | grep -q "^${service}[[:space:]]"
}

service_enable_now() {
  local service="$1"
  service_exists "$service" || return 0
  run systemctl enable --now "$service"
}

detect_ssh_port() {
  local port="22"
  if command_exists sshd; then
    port="$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}')"
  fi
  printf '%s' "${port:-22}"
}
