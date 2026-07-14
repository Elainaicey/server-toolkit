#!/usr/bin/env bash

pkg_installed() {
  local pkg="$1"
  case "$OS_FAMILY" in
    debian) dpkg -s "$pkg" >/dev/null 2>&1 ;;
    rhel) rpm -q "$pkg" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

wait_package_manager() {
  [[ "$OS_FAMILY" == "debian" ]] || return 0
  command_exists fuser || return 0
  local waited=0 max_wait=180
  local locks=(/var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock)
  while fuser "${locks[@]}" >/dev/null 2>&1; do
    (( waited == 0 )) && log_info "检测到 apt/dpkg 锁，正在等待释放..."
    (( waited >= max_wait )) && { log_warn "等待软件包锁超过 ${max_wait}s，继续尝试执行。"; return 0; }
    sleep 3
    waited=$((waited + 3))
  done
}

apt_get() {
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  export UCF_FORCE_CONFFOLD=1
  wait_package_manager
  run apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -o Acquire::Retries=3 \
    "$@"
}

pkg_update_index() {
  [[ "$SKIP_UPDATE" -eq 1 ]] && { log_info "已跳过软件源刷新。"; return 0; }
  log_step "刷新软件源"
  case "$OS_FAMILY" in
    debian) apt_get update ;;
    rhel) run "$PM" -y makecache || true ;;
  esac
}

pkg_upgrade_system() {
  [[ "$UPGRADE_SYSTEM" -eq 1 ]] || { log_info "未启用系统软件包升级。"; return 0; }
  log_step "升级已安装的软件包"
  case "$OS_FAMILY" in
    debian) apt_get -y upgrade ;;
    rhel) run "$PM" -y update ;;
  esac
}

pkg_install() {
  local pkg
  for pkg in "$@"; do
    [[ -z "$pkg" ]] && continue
    if pkg_installed "$pkg"; then
      log_info "已安装：$pkg"
      continue
    fi
    log_info "正在安装：$pkg"
    case "$OS_FAMILY" in
      debian) apt_get install -y "$pkg" || log_warn "安装失败：$pkg" ;;
      rhel) run "$PM" install -y "$pkg" || log_warn "安装失败：$pkg" ;;
    esac
  done
}

pkg_install_one_of() {
  local pkg
  for pkg in "$@"; do
    pkg_installed "$pkg" && { log_info "已安装：$pkg"; return 0; }
  done
  for pkg in "$@"; do
    log_info "尝试安装：$pkg"
    case "$OS_FAMILY" in
      debian) apt_get install -y "$pkg" && return 0 ;;
      rhel) run "$PM" install -y "$pkg" && return 0 ;;
    esac
  done
  log_warn "以下候选包均未安装成功：$*"
  return 1
}

pkg_cleanup() {
  log_step "清理软件包缓存"
  case "$OS_FAMILY" in
    debian) run apt-get autoremove -y || true; run apt-get clean || true ;;
    rhel) run "$PM" clean all || true ;;
  esac
}
