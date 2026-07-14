#!/usr/bin/env bash

base_packages() {
  if [[ "$OS_FAMILY" == "debian" ]]; then
    printf '%s\n' ca-certificates curl wget git vim unzip zip tar gzip xz-utils htop tmux lsof psmisc net-tools iproute2 dnsutils jq sudo bash-completion gnupg lsb-release chrony rsync
  else
    printf '%s\n' ca-certificates curl wget git vim-enhanced unzip zip tar gzip xz htop tmux lsof psmisc net-tools iproute bind-utils jq sudo bash-completion gnupg2 chrony rsync policycoreutils-python-utils
  fi
}

base_install_core() {
  log_step "安装基础工具"
  mapfile -t pkgs < <(base_packages)
  pkg_install "${pkgs[@]}"
}

base_set_timezone() {
  local tz="$1"
  [[ -n "$tz" ]] || return 0
  [[ -f "/usr/share/zoneinfo/$tz" ]] || { log_warn "未找到时区：$tz"; return 0; }
  backup_file /etc/timezone
  run timedatectl set-timezone "$tz"
}

base_fix_hosts_resolution() {
  local host
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  [[ -n "$host" ]] || return 0
  getent hosts "$host" >/dev/null 2>&1 && return 0
  log_step "修复本机主机名解析：$host"
  backup_file /etc/hosts
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 向 /etc/hosts 追加：127.0.1.1 $host"
  else
    printf '\n127.0.1.1 %s\n' "$host" >> /etc/hosts
  fi
}

base_enable_time_sync() {
  log_step "启用时间同步"
  command_exists timedatectl && run timedatectl set-ntp true || true
  if [[ "$OS_FAMILY" == "rhel" ]]; then
    systemctl list-unit-files | grep -q '^chronyd\.service' && run systemctl enable --now chronyd || true
  else
    systemctl list-unit-files | grep -q '^chrony\.service' && run systemctl enable --now chrony || true
  fi
}

base_create_swap() {
  local size="$1"
  [[ -n "$size" ]] || return 0
  [[ "$size" =~ ^[0-9]+[MmGg]$ ]] || die "Swap 大小格式无效：$size"
  swapon --show | grep -q . && { log_info "系统已有 swap，跳过。"; return 0; }
  [[ -f /swapfile ]] && { log_warn "/swapfile 已存在但未启用，为避免覆盖已跳过。"; return 0; }
  log_step "创建 swapfile：$size"
  if command_exists fallocate; then
    run fallocate -l "$size" /swapfile
  else
    local count
    case "$size" in
      *G|*g) count="$(( ${size%[Gg]} * 1024 ))" ;;
      *M|*m) count="${size%[Mm]}" ;;
    esac
    run dd if=/dev/zero of=/swapfile bs=1M count="$count" status=progress
  fi
  run chmod 600 /swapfile
  run mkswap /swapfile
  run swapon /swapfile
  backup_file /etc/fstab
  grep -qE '^/swapfile\s+' /etc/fstab 2>/dev/null || {
    [[ "$DRY_RUN" -eq 1 ]] && log_info "[DRY-RUN] 向 /etc/fstab 写入 swapfile" || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  }
}

base_enable_auto_updates() {
  log_step "启用安全自动更新"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install unattended-upgrades apt-listchanges
    backup_file /etc/apt/apt.conf.d/20auto-upgrades
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[DRY-RUN] 写入 /etc/apt/apt.conf.d/20auto-upgrades"
    else
      cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APTCONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APTCONF
    fi
    run systemctl enable --now unattended-upgrades || true
  else
    pkg_install dnf-automatic yum-cron
    systemctl list-unit-files | grep -q '^dnf-automatic\.timer' && run systemctl enable --now dnf-automatic.timer || true
  fi
}

base_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    print_title "快速初始化"
    cat <<'MENU'
1. 安装基础工具
2. 启用时间同步
3. 修复 /etc/hosts 主机名解析
4. 设置时区
5. 创建 Swapfile
6. 启用安全自动更新
7. 执行推荐基础初始化
0. 返回
MENU
    local choice
    choice="$(ask_input "请选择" "0")"
    case "$choice" in
      1) pkg_update_index; base_install_core ;;
      2) base_enable_time_sync ;;
      3) base_fix_hosts_resolution ;;
      4) base_set_timezone "$(ask_input "时区" "Asia/Shanghai")" ;;
      5) base_create_swap "$(ask_input "Swap 大小" "1G")" ;;
      6) pkg_update_index; base_enable_auto_updates ;;
      7)
        pkg_update_index
        base_install_core
        base_enable_time_sync
        base_fix_hosts_resolution
        if ask_yes_no "是否设置时区为 Asia/Shanghai？" "Y"; then
          base_set_timezone "Asia/Shanghai"
        fi
        ;;
      0) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}
