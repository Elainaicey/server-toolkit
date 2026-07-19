#!/usr/bin/env bash

security_firewall_status() {
  ui_header "UFW 状态"
  if command_exists ufw; then
    ufw status numbered
  else
    ui_empty "UFW 未安装"
  fi
}

security_enable_firewall() {
  local ssh_port raw old_ifs port; local ports=()
  ssh_port="$(detect_ssh_port)"
  ui_header "启用基础防火墙"
  ui_kv "保留 SSH" "$ssh_port/tcp"
  ui_kv "默认策略" "拒绝入站，允许出站"
  raw="$(read_input "额外 TCP 端口（逗号分隔，可留空）" "")"
  if [[ -n "$raw" ]]; then
    old_ifs="$IFS"
    IFS=',' read -r -a ports <<<"${raw// /}"
    IFS="$old_ifs"
    for port in "${ports[@]}"; do
      valid_port "$port" || { warn "无效端口：$port"; return 1; }
    done
  fi
  confirm "安装并启用 UFW？" || return 0
  require_root
  package_install ufw
  run ufw allow "$ssh_port/tcp"
  for port in "${ports[@]}"; do
    run ufw allow "$port/tcp"
  done
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw --force enable
  audit "action=firewall-enable ssh_port=$ssh_port extra=${raw:-none}"
}

security_firewall_rule() {
  local mode="$1" port; command_exists ufw || { warn "请先启用 UFW。"; return 1; }
  port="$(read_input "TCP 端口" "443")"; valid_port "$port" || { warn "端口无效。"; return 1; }
  local verb="放行"
  if [[ "$mode" == "delete" ]]; then
    verb="删除放行规则"
  fi
  confirm "$verb $port/tcp？" || return 0; require_root
  if [[ "$mode" == "delete" ]]; then run ufw --force delete allow "$port/tcp"; else run ufw allow "$port/tcp"; fi
  audit "action=firewall-rule mode=$mode port=$port"
}

security_public_key_exists() { find /root /home -maxdepth 3 -path '*/.ssh/authorized_keys' -type f -s 2>/dev/null | grep -q .; }

security_restore_ssh_files() {
  local main_config="$1" config="$2" config_existed="$3"
  if [[ -e "$BACKUP_SESSION$main_config" ]]; then
    cp -a "$BACKUP_SESSION$main_config" "$main_config"
  fi
  if [[ "$config_existed" -eq 1 && -e "$BACKUP_SESSION$config" ]]; then
    cp -a "$BACKUP_SESSION$config" "$config"
  else
    rm -f -- "$config"
  fi
}

security_configure_ssh() {
  local current_port new_port disable_password=0 disable_root=0 key_label="否" password_label="保持现状" root_label="保持现状"
  current_port="$(detect_ssh_port)"
  if security_public_key_exists; then key_label="是"; fi
  ui_header "SSH 安全向导"
  ui_kv "当前端口" "$current_port"
  ui_kv "已检测公钥" "$key_label"
  new_port="$(read_input "SSH 端口" "$current_port")"
  valid_port "$new_port" || { warn "SSH 端口无效。"; return 1; }
  if confirm "禁用密码登录？"; then disable_password=1; fi
  if confirm "禁止 root 直接登录？"; then disable_root=1; fi
  if [[ "$disable_password" -eq 1 ]] && ! security_public_key_exists; then
    warn "未检测到 authorized_keys，保持密码登录。"
    disable_password=0
  fi
  if [[ "$disable_password" -eq 1 ]]; then password_label="禁用"; fi
  if [[ "$disable_root" -eq 1 ]]; then root_label="禁用"; fi
  ui_section "变更摘要"
  ui_kv "端口" "$new_port"
  ui_kv "密码登录" "$password_label"
  ui_kv "root 登录" "$root_label"
  confirm "应用以上 SSH 设置？" || return 0; require_root
  if [[ "$new_port" != "$current_port" ]] && ss -H -ltn "sport = :$new_port" 2>/dev/null | grep -q .; then warn "端口 $new_port 已被占用。"; return 1; fi
  command_exists sshd || die "未找到 sshd。"
  local main_config=/etc/ssh/sshd_config dropin_dir=/etc/ssh/sshd_config.d config=/etc/ssh/sshd_config.d/99-server-toolkit.conf config_existed=0
  if [[ -e "$config" ]]; then config_existed=1; fi
  backup_file "$main_config"
  backup_file "$config"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将写入并验证 $config。"; return 0; fi
  mkdir -p "$dropin_dir"
  grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/(\*\.conf|99-server-toolkit\.conf)' "$main_config" || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$main_config"
  {
    printf '# Managed by Server Toolkit\nPort %s\n' "$new_port"
    if [[ "$disable_password" -eq 1 ]]; then
      printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n'
    fi
    if [[ "$disable_root" -eq 1 ]]; then
      printf 'PermitRootLogin no\n'
    fi
  } >"$config"; chmod 0644 "$config"
  if ! sshd -t -f "$main_config"; then
    security_restore_ssh_files "$main_config" "$config" "$config_existed"
    warn "SSH 验证失败，已恢复配置。"
    return 1
  fi
  if [[ "$new_port" != "$current_port" ]] && command_exists ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    if ! ufw allow "$new_port/tcp"; then
      security_restore_ssh_files "$main_config" "$config" "$config_existed"
      warn "无法放行新的 SSH 端口，已恢复配置。"
      return 1
    fi
  fi
  local ssh_service=""
  if service_exists ssh.service; then
    ssh_service=ssh.service
  elif service_exists sshd.service; then
    ssh_service=sshd.service
  fi
  if [[ -z "$ssh_service" ]]; then
    security_restore_ssh_files "$main_config" "$config" "$config_existed"
    warn "未找到 SSH 服务，已恢复配置。"
    return 1
  fi
  if ! systemctl restart "$ssh_service"; then
    security_restore_ssh_files "$main_config" "$config" "$config_existed"
    systemctl restart "$ssh_service" 2>/dev/null || true
    warn "SSH 重启失败，已恢复旧配置。"
    return 1
  fi
  audit "action=ssh-config port=$new_port password_disabled=$disable_password root_disabled=$disable_root"
  warn "请保留当前会话，并在新窗口验证登录。"
}

security_auth_log() {
  ui_header "近期 SSH 登录事件"
  journalctl -u ssh.service -u sshd.service --since '-24 hours' --no-pager 2>/dev/null | grep -Ei 'accepted|failed|invalid user|disconnect' | tail -n 80 || ui_empty "没有可显示的事件"
}

security_menu() {
  local choice
  while true; do
    ui_clear
    ui_header "安全中心"
    ui_item 1 "UFW 状态"
    ui_item 2 "启用基础防火墙"
    ui_item 3 "放行 TCP 端口"
    ui_item 4 "删除端口规则"
    ui_item 5 "SSH 安全向导"
    ui_item 6 "SSH 登录事件"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) security_firewall_status ;;
      2) security_enable_firewall || true ;;
      3) security_firewall_rule add || true ;;
      4) security_firewall_rule delete || true ;;
      5) security_configure_ssh || true ;;
      6) security_auth_log ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
