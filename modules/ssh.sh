#!/usr/bin/env bash

ssh_public_key_exists() {
  find /root /home -maxdepth 3 -path '*/.ssh/authorized_keys' -type f -s 2>/dev/null | grep -q .
}

ssh_ensure_include() {
  [[ -f /etc/ssh/sshd_config ]] || die "未找到 /etc/ssh/sshd_config"
  safe_mkdir /etc/ssh/sshd_config.d
  if ! grep -Eq '^\s*Include\s+/etc/ssh/sshd_config\.d/(\*\.conf|99-server-toolkit\.conf)' /etc/ssh/sshd_config; then
    backup_file /etc/ssh/sshd_config
    run sed -i '1i Include /etc/ssh/sshd_config.d/99-server-toolkit.conf' /etc/ssh/sshd_config
  fi
}

ssh_write_config() {
  local port="$1"
  local disable_password="$2"
  local disable_root="$3"
  local conf="/etc/ssh/sshd_config.d/99-server-toolkit.conf"
  ssh_ensure_include
  backup_file "$conf"
  if [[ "$disable_password" -eq 1 ]] && ! ssh_public_key_exists; then
    if ! ask_yes_no "未检测到 authorized_keys，仍然要禁用密码登录吗？" "N"; then
      disable_password=0
    fi
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 写入 $conf"
    return 0
  fi
  {
    echo '# Managed by Server Toolkit'
    [[ -n "$port" ]] && echo "Port $port"
    [[ "$disable_root" -eq 1 ]] && echo 'PermitRootLogin no'
    if [[ "$disable_password" -eq 1 ]]; then
      echo 'PasswordAuthentication no'
      echo 'KbdInteractiveAuthentication no'
      echo 'ChallengeResponseAuthentication no'
      echo 'PubkeyAuthentication yes'
    fi
    echo 'ClientAliveInterval 300'
    echo 'ClientAliveCountMax 2'
    echo 'LoginGraceTime 30'
    echo 'MaxAuthTries 4'
    echo 'X11Forwarding no'
  } > "$conf"
  chmod 0644 "$conf"
}

ssh_restart_checked() {
  if ! sshd -t -f /etc/ssh/sshd_config; then
    die "SSH 配置检查失败。备份目录：$BACKUP_DIR"
  fi
  run systemctl restart "$SSH_SERVICE"
  log_warn "请保留当前 SSH 会话，另开一个窗口测试新连接成功后再关闭。"
}

ssh_apply_profile_hardening() {
  local port="${1:-}"
  local disable_password="${2:-0}"
  local disable_root="${3:-0}"
  detect_system
  [[ -n "$port" ]] && firewall_allow_port "$port"
  firewall_allow_port "$SSH_PORT"
  ssh_write_config "$port" "$disable_password" "$disable_root"
  ssh_restart_checked
  if [[ "${4:-}" == "fail2ban" ]]; then
    ssh_install_fail2ban "${port:-$SSH_PORT}"
  fi
}

ssh_install_fail2ban() {
  local port="${1:-$SSH_PORT}"
  log_step "安装并配置 SSH fail2ban"
  [[ "$OS_FAMILY" == "rhel" ]] && pkg_install epel-release
  pkg_install fail2ban
  safe_mkdir /etc/fail2ban/jail.d
  backup_file /etc/fail2ban/jail.d/sshd.local
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 写入 fail2ban sshd jail"
  else
    cat > /etc/fail2ban/jail.d/sshd.local <<JAIL
[sshd]
enabled = true
port = ${port}
maxretry = 5
findtime = 10m
bantime = 1h
JAIL
  fi
  systemctl list-unit-files | grep -q '^fail2ban\.service' && run systemctl enable --now fail2ban && run systemctl restart fail2ban || true
}

ssh_menu() {
  require_root
  detect_system
  print_title "SSH 安全配置"
  echo "当前 SSH 服务：$SSH_SERVICE"
  echo "当前 SSH 端口：$SSH_PORT"
  echo "是否检测到公钥：$(ssh_public_key_exists && echo 是 || echo 否)"
  local new_port="" disable_password=0 disable_root=0
  if ask_yes_no "是否修改 SSH 端口？" "N"; then
    new_port="$(ask_input "新的 SSH 端口" "2222")"
  fi
  ask_yes_no "是否禁用 SSH 密码登录？" "N" && disable_password=1
  ask_yes_no "是否禁止 root 直接 SSH 登录？" "N" && disable_root=1
  if ask_yes_no "是否应用 SSH 修改？" "N"; then
    ssh_apply_profile_hardening "$new_port" "$disable_password" "$disable_root"
  fi
  if ask_yes_no "是否安装/配置 fail2ban？" "Y"; then
    ssh_install_fail2ban "${new_port:-$SSH_PORT}"
  fi
  pause
}
