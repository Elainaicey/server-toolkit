#!/usr/bin/env bash

security_firewall_status() {
  ui_page "UFW 状态" "主机防火墙状态与编号规则"
  if command_exists ufw; then
    ufw status numbered
  else
    ui_empty "UFW 未安装"
  fi
}

security_audit() {
  ui_page "安全基线检查" "防火墙、SSH、特权账户、Fail2ban 与重启状态"
  local ssh_settings uid0_count
  if command_exists ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    doctor_result pass "UFW 已启用"
  else
    doctor_result warn "主机防火墙未启用"
  fi
  if command_exists sshd; then
    ssh_settings="$(sshd -T 2>/dev/null || true)"
    if grep -q '^passwordauthentication no$' <<<"$ssh_settings"; then doctor_result pass "SSH 密码登录已禁用"; else doctor_result warn "SSH 仍允许密码登录"; fi
    if grep -Eq '^permitrootlogin (no|prohibit-password)$' <<<"$ssh_settings"; then doctor_result pass "root 登录已限制"; else doctor_result warn "root 可直接通过 SSH 登录"; fi
    ui_kv "SSH 端口" "$(awk '/^port /{print $2;exit}' <<<"$ssh_settings")"
  else
    doctor_result warn "无法检查 sshd 有效配置"
  fi
  uid0_count="$(awk -F: '$3==0{count++}END{print count+0}' /etc/passwd)"
  if [[ "$uid0_count" -eq 1 ]]; then doctor_result pass "只有一个 UID 0 账户"; else doctor_result warn "检测到 $uid0_count 个 UID 0 账户"; fi
  if command_exists fail2ban-client && fail2ban-client ping >/dev/null 2>&1; then
    doctor_result pass "Fail2ban 正在运行"
  else
    doctor_result warn "Fail2ban 未安装或未运行"
  fi
  if [[ -f /var/run/reboot-required ]]; then doctor_result warn "系统提示需要重启"; else doctor_result pass "没有待处理的重启提示"; fi
}

security_exposed_ports() {
  ui_page "公网监听端口" "识别监听所有 IPv4/IPv6 地址的服务"
  if ! command_exists ss; then
    warn "缺少 ss 命令。"
    return 1
  fi
  printf '  %-8s %-28s %s\n' "协议" "监听地址" "进程"
  ss -H -lntup 2>/dev/null | awk '
    $5 ~ /^(0\.0\.0\.0:|\[::\]:|\*:)/ {
      printf "  %-8s %-28s %s\n",$1,$5,substr($0,index($0,$7))
      found=1
    }
    END {if(!found) print "  — 没有检测到监听所有地址的端口"}
  '
  ui_note "监听所有地址不代表一定可从公网访问，还需要结合云防火墙、UFW 和 Docker 规则判断。"
}

security_fail2ban() {
  ui_page "Fail2ban 状态" "服务连通性、Jail 和封禁统计"
  if ! command_exists fail2ban-client; then
    ui_empty "Fail2ban 未安装，可在软件管理中搜索 fail2ban。"
    return 0
  fi
  fail2ban-client status 2>/dev/null || { warn "Fail2ban 服务未运行。"; return 1; }
  local jails jail
  jails="$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p')"
  if [[ -n "$jails" ]]; then
    ui_section "Jail 详情"
    while IFS= read -r jail; do
      jail="${jail// /}"
      [[ -n "$jail" ]] && fail2ban-client status "$jail" 2>/dev/null | sed -n '1,12p'
    done < <(tr ',' '\n' <<<"$jails")
  fi
}

security_tls_inspect() {
  local target port endpoint pem certificate
  target="$(read_input "域名或 IP" "github.com")"
  valid_network_target "$target" || { warn "目标格式无效。"; return 1; }
  port="$(read_input "TLS 端口" "443")"
  valid_port "$port" || { warn "端口无效。"; return 1; }
  command_exists openssl || { warn "未安装 openssl。"; return 1; }
  command_exists timeout || { warn "缺少 timeout 命令。"; return 1; }
  endpoint="$target:$port"
  if [[ "$target" == *:* ]]; then endpoint="[$target]:$port"; fi
  ui_page "TLS 证书检查" "$target:$port"
  pem="$(timeout 12 openssl s_client -servername "$target" -connect "$endpoint" </dev/null 2>/dev/null || true)"
  certificate="$(openssl x509 -noout -subject -issuer -serial -dates -fingerprint -sha256 2>/dev/null <<<"$pem" || true)"
  [[ -n "$certificate" ]] || { warn "未能取得有效证书。"; return 1; }
  printf '%s\n' "$certificate"
  ui_section "证书主机名"
  openssl x509 -noout -ext subjectAltName 2>/dev/null <<<"$pem" || true
}

security_enable_firewall() {
  local ssh_port raw old_ifs port; local ports=()
  ssh_port="$(detect_ssh_port)"
  ui_page "启用基础防火墙" "保留当前 SSH 端口并应用默认入站策略"
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
  ui_page "UFW 端口规则" "添加或删除一个明确的 TCP 放行端口"
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
  ui_page "SSH 安全向导" "端口、公钥、密码登录与 root 登录策略"
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
  ui_page "SSH 登录事件" "最近 24 小时的成功、失败和无效用户记录"
  journalctl -u ssh.service -u sshd.service --since '-24 hours' --no-pager 2>/dev/null | grep -Ei 'accepted|failed|invalid user|disconnect' | tail -n 80 || ui_empty "没有可显示的事件"
}

security_menu() {
  local choice
  while true; do
    ui_page "安全中心" "检查暴露面，管理主机防火墙与 SSH 登录安全"
    ui_section "评估与观察" "primary"
    ui_item 1 "安全基线检查" "防火墙、SSH、UID 0、Fail2ban 与重启"
    ui_item 2 "公网监听端口" "识别监听所有地址的服务"
    ui_item 3 "UFW 状态"
    ui_section "主机防护" "accent"
    ui_item 4 "启用基础防火墙"
    ui_item 5 "放行 TCP 端口"
    ui_item 6 "删除端口规则"
    ui_item 7 "SSH 安全向导"
    ui_section "事件与证书" "primary"
    ui_item 8 "SSH 登录事件"
    ui_item 9 "Fail2ban 状态"
    ui_item 10 "TLS 证书检查" "签发者、有效期、指纹与主机名"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) security_audit ;;
      2) security_exposed_ports || true ;;
      3) security_firewall_status ;;
      4) security_enable_firewall || true ;;
      5) security_firewall_rule add || true ;;
      6) security_firewall_rule delete || true ;;
      7) security_configure_ssh || true ;;
      8) security_auth_log ;;
      9) security_fail2ban || true ;;
      10) security_tls_inspect || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
