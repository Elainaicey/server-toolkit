#!/usr/bin/env bash

OS_ID=""; OS_NAME=""; OS_CODENAME=""; ARCH=""
CPU_CORES=""; MEMORY_MB=""; MEMORY_USED_MB=""; SWAP_MB=""; SWAP_USED_MB=""; ROOT_USAGE=""; ROOT_USED_PERCENT=""; VIRTUALIZATION=""; LOAD_AVERAGE=""; UPTIME_TEXT=""
PACKAGE_INDEX_UPDATED=0

platform_detect() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck source=/dev/null
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_NAME="${PRETTY_NAME:-$OS_ID ${VERSION_ID:-unknown}}"
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  case "$OS_ID" in debian|ubuntu) ;; *) die "当前仅支持 Debian 和 Ubuntu，检测到：$OS_NAME" ;; esac
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  CPU_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '?')"
  MEMORY_MB="$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || printf '?')"
  MEMORY_USED_MB="$(awk '/MemTotal/{total=$2}/MemAvailable/{available=$2}END{printf "%.0f",(total-available)/1024}' /proc/meminfo 2>/dev/null || printf '0')"
  SWAP_MB="$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || printf '0')"
  SWAP_USED_MB="$(awk '/SwapTotal/{total=$2}/SwapFree/{free=$2}END{printf "%.0f",(total-free)/1024}' /proc/meminfo 2>/dev/null || printf '0')"
  ROOT_USAGE="$(df -h / 2>/dev/null | awk 'NR == 2 {print $3 "/" $2 " (" $5 ")"}')"
  ROOT_USED_PERCENT="$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')"
  VIRTUALIZATION="$(systemd-detect-virt 2>/dev/null || printf 'unknown')"
  LOAD_AVERAGE="$(awk '{print $1 " " $2 " " $3}' /proc/loadavg 2>/dev/null || printf '?')"
  UPTIME_TEXT="$(uptime -p 2>/dev/null | sed 's/^up //' || printf '?')"
}

package_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'; }

package_wait_for_lock() {
  command_exists fuser || return 0
  local waited=0
  local locks=(/var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock)
  while fuser "${locks[@]}" >/dev/null 2>&1; do
    (( waited == 0 )) && info "APT 正被其他进程使用，等待锁释放……"
    (( waited >= 180 )) && die "等待 APT 锁超过 180 秒，请稍后重试。"
    sleep 3; waited=$((waited + 3))
  done
}

apt_run() {
  package_wait_for_lock
  run env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::Retries=3 "$@"
}

package_update_index() { [[ "$PACKAGE_INDEX_UPDATED" -eq 1 ]] && return 0; info "刷新软件索引……"; apt_run update; PACKAGE_INDEX_UPDATED=1; }
package_invalidate_index() { PACKAGE_INDEX_UPDATED=0; }

package_install() {
  local requested=("$@") missing=() package display=""
  for package in "${requested[@]}"; do [[ -n "$package" ]] && ! package_installed "$package" && missing+=("$package"); done
  ((${#missing[@]} > 0)) || { info "已经安装，无需操作。"; return 0; }
  package_update_index; printf -v display '%s ' "${missing[@]}"; info "将安装系统包：${display% }"
  apt_run install -y "${missing[@]}"
}

package_remove() {
  local requested=("$@") installed=() package display=""
  for package in "${requested[@]}"; do [[ -n "$package" ]] && package_installed "$package" && installed+=("$package"); done
  ((${#installed[@]} > 0)) || { info "软件未安装。"; return 0; }
  printf -v display '%s ' "${installed[@]}"; info "将移除系统包：${display% }"
  apt_run remove -y "${installed[@]}"
}

package_upgradable_count() { apt list --upgradable 2>/dev/null | sed '1d' | grep -c . || true; }

service_exists() {
  command_exists systemctl && systemctl list-unit-files --type=service --no-legend 2>/dev/null |
    awk -v service="$1" '$1 == service { found=1 } END { exit !found }'
}
service_enable_now() {
  if service_exists "$1"; then
    run systemctl enable --now "$1"
  fi
}
service_state() {
  local state
  state="$(systemctl is-active "$1" 2>/dev/null || true)"
  printf '%s' "${state:-inactive}"
}

detect_ssh_port() {
  local port="22"
  command_exists sshd && port="$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}')"
  printf '%s' "${port:-22}"
}
