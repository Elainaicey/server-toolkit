#!/usr/bin/env bash

system_validate_hostname() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}[A-Za-z0-9]$ || "$name" =~ ^[A-Za-z0-9]$ ]]
}

system_set_hostname() {
  local name="$1"
  [[ -n "$name" ]] || return 0
  system_validate_hostname "$name" || die "主机名不合法：$name"
  log_step "设置主机名：$name"
  backup_file /etc/hostname
  backup_file /etc/hosts
  run hostnamectl set-hostname "$name"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 更新 /etc/hosts 中的本机主机名解析"
    return 0
  fi

  if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts 2>/dev/null; then
    sed -i "s/^127\\.0\\.1\\.1[[:space:]].*/127.0.1.1 ${name}/" /etc/hosts
  elif ! getent hosts "$name" >/dev/null 2>&1; then
    printf '\n127.0.1.1 %s\n' "$name" >> /etc/hosts
  fi
}

system_set_locale() {
  local locale_name="$1"
  [[ -n "$locale_name" ]] || return 0
  pkg_update_index
  log_step "设置系统 Locale：$locale_name"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install locales
    backup_file /etc/locale.gen
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[DRY-RUN] 启用 ${locale_name} 并执行 locale-gen/update-locale"
    else
      sed -i "s/^# *${locale_name} UTF-8/${locale_name} UTF-8/" /etc/locale.gen || true
      grep -q "^${locale_name} UTF-8" /etc/locale.gen || echo "${locale_name} UTF-8" >> /etc/locale.gen
    fi
    run locale-gen "$locale_name"
    run update-locale "LANG=${locale_name}"
  else
    pkg_install glibc-langpack-en glibc-langpack-zh
    run localectl set-locale "LANG=${locale_name}" || true
  fi
}

system_create_admin_user() {
  local user="$1"
  local pubkey="${2:-}"
  [[ -n "$user" ]] || return 0
  [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "用户名不合法：$user"
  log_step "创建/配置管理员用户：$user"
  if ! id "$user" >/dev/null 2>&1; then
    run useradd -m -s /bin/bash "$user"
  else
    log_info "用户已存在：$user"
  fi
  if [[ "$OS_FAMILY" == "debian" ]]; then
    run usermod -aG sudo "$user"
  else
    run usermod -aG wheel "$user"
  fi
  if [[ -n "$pubkey" ]]; then
    local home_dir
    home_dir="$(getent passwd "$user" | cut -d: -f6)"
    home_dir="${home_dir:-/home/$user}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[DRY-RUN] 写入 ${home_dir}/.ssh/authorized_keys"
    else
      mkdir -p "${home_dir}/.ssh"
      printf '%s\n' "$pubkey" > "${home_dir}/.ssh/authorized_keys"
      chmod 700 "${home_dir}/.ssh"
      chmod 600 "${home_dir}/.ssh/authorized_keys"
      chown -R "${user}:${user}" "${home_dir}/.ssh"
    fi
  fi
}

system_settings_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    ui_panel_start "系统设置中心"
    ui_panel_line "$(printf '%b主机名%b  %s' "$DIM" "$NC" "$(hostname 2>/dev/null || echo 未知)")"
    ui_panel_line "$(printf '%b时区%b    %s' "$DIM" "$NC" "$(timedatectl show -p Timezone --value 2>/dev/null || echo 未知)")"
    ui_panel_line "$(printf '%bLocale%b  %s' "$DIM" "$NC" "${LANG:-未知}")"
    ui_panel_line "$(printf '%bSwap%b    %s MB' "$DIM" "$NC" "${SWAP_TOTAL_MB:-0}")"
    ui_panel_rule
    ui_panel_line "[01] 设置主机名              [02] 设置时区"
    ui_panel_line "[03] 设置系统 Locale         [04] 修复 hosts 主机名解析"
    ui_panel_line "[05] 创建/配置 sudo 用户     [06] 创建 Swapfile"
    ui_panel_line "[07] 启用时间同步            [08] 启用安全自动更新"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) system_set_hostname "$(ask_input "请输入新主机名" "$(hostname -s 2>/dev/null || echo vps)")" ;;
      2|02) base_set_timezone "$(ask_input "请输入时区" "Asia/Shanghai")" ;;
      3|03) system_set_locale "$(ask_input "请输入 Locale" "en_US.UTF-8")" ;;
      4|04) base_fix_hosts_resolution ;;
      5|05)
        local user pubkey
        user="$(ask_input "请输入用户名" "admin")"
        pubkey="$(ask_input "请输入 SSH 公钥，可留空" "")"
        system_create_admin_user "$user" "$pubkey"
        ;;
      6|06) base_create_swap "$(ask_input "Swap 大小，例如 1G/2G/512M" "1G")" ;;
      7|07) base_enable_time_sync ;;
      8|08) base_enable_auto_updates ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
    detect_system || true
  done
}
