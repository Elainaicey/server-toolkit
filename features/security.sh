#!/usr/bin/env bash

security_enable_firewall() {
  local ssh_port extra raw old_ifs port
  local ports=()
  ssh_port="$(detect_ssh_port)"
  ui_header "启用基础防火墙"
  ui_kv "SSH 端口" "$ssh_port"
  ui_kv "默认策略" "拒绝入站，允许出站"
  raw="$(read_input "额外放行的 TCP 端口（逗号分隔，可留空）" "")"
  if [[ -n "$raw" ]]; then
    old_ifs="$IFS"
    IFS=',' read -r -a ports <<<"${raw// /}"
    IFS="$old_ifs"
    for port in "${ports[@]}"; do
      valid_port "$port" || { warn "无效端口：$port"; return 1; }
    done
  fi
  confirm "安装并启用 UFW？" || { warn "已取消。"; return 0; }
  require_root
  package_install ufw
  run ufw allow "$ssh_port/tcp"
  for extra in "${ports[@]}"; do
    run ufw allow "$extra/tcp"
  done
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw --force enable
  [[ "$DRY_RUN" -eq 1 ]] || ufw status verbose
}

security_public_key_exists() {
  find /root /home -maxdepth 3 -path '*/.ssh/authorized_keys' -type f -s 2>/dev/null | grep -q .
}

security_configure_ssh() {
  local current_port new_port disable_password=0 disable_root=0
  current_port="$(detect_ssh_port)"
  ui_header "SSH 安全设置"
  ui_kv "当前端口" "$current_port"
  local public_key_label="否"
  security_public_key_exists && public_key_label="是"
  ui_kv "已检测公钥" "$public_key_label"
  new_port="$(read_input "SSH 端口" "$current_port")"
  valid_port "$new_port" || { warn "SSH 端口无效。"; return 1; }
  confirm "禁用密码登录？" && disable_password=1
  confirm "禁止 root 直接登录？" && disable_root=1
  if [[ "$disable_password" -eq 1 ]] && ! security_public_key_exists; then
    warn "未检测到 authorized_keys，不能安全地禁用密码登录。"
    disable_password=0
  fi
  printf '\n'
  local password_label="保持现状" root_label="保持现状"
  [[ "$disable_password" -eq 1 ]] && password_label="禁用"
  [[ "$disable_root" -eq 1 ]] && root_label="禁用"
  ui_kv "新端口" "$new_port"
  ui_kv "密码登录" "$password_label"
  ui_kv "root 登录" "$root_label"
  confirm "应用以上 SSH 设置？" || { warn "已取消。"; return 0; }
  require_root

  if [[ "$new_port" != "$current_port" ]] && ss -H -ltn "sport = :$new_port" 2>/dev/null | grep -q .; then
    warn "端口 $new_port 已被占用。"
    return 1
  fi
  command_exists sshd || die "未找到 sshd。"

  local main_config=/etc/ssh/sshd_config
  local dropin_dir=/etc/ssh/sshd_config.d
  local config=$dropin_dir/99-server-toolkit.conf
  local config_existed=0
  [[ -e "$config" ]] && config_existed=1
  backup_file "$main_config"
  backup_file "$config"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将写入 $config 并验证 SSH 配置。"
    return 0
  fi

  mkdir -p "$dropin_dir"
  if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/(\*\.conf|99-server-toolkit\.conf)' "$main_config"; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$main_config"
  fi
  {
    printf '# Managed by Server Toolkit\n'
    printf 'Port %s\n' "$new_port"
    [[ "$disable_password" -eq 1 ]] && printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n'
    [[ "$disable_root" -eq 1 ]] && printf 'PermitRootLogin no\n'
  } >"$config"
  chmod 0644 "$config"

  if ! sshd -t -f "$main_config"; then
    if [[ "$config_existed" -eq 1 && -e "$BACKUP_SESSION$config" ]]; then
      cp -a "$BACKUP_SESSION$config" "$config"
    else
      rm -f "$config"
    fi
    warn "SSH 配置验证失败。备份位于：${BACKUP_SESSION:-$BACKUP_ROOT}"
    return 1
  fi
  if command_exists ufw; then
    ufw allow "$new_port/tcp"
  fi
  if service_exists ssh.service; then
    systemctl restart ssh.service
  elif service_exists sshd.service; then
    systemctl restart sshd.service
  else
    warn "未找到 SSH systemd 服务，请手动重启 SSH。"
  fi
  warn "请保留当前会话，并在新窗口验证 SSH 登录后再关闭。"
}
