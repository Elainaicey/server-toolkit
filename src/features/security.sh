#!/usr/bin/env bash

security_firewall_status() {
  ui_page "UFW 状态" "默认策略、日志级别与编号规则"
  if command_exists ufw; then
    ufw status verbose
    ui_section "编号规则" "accent"
    ufw status numbered
  else
    ui_empty "UFW 未安装"
  fi
}

security_audit() {
  ui_page "安全基线检查" "防火墙、SSH、特权账户、Fail2ban 与重启状态"
  local ssh_settings uid0_count
  if platform_firewall_active; then
    ui_check pass "UFW 已启用"
  else
    ui_check warn "主机防火墙未启用"
  fi
  if command_exists sshd; then
    ssh_settings="$(sshd -T 2>/dev/null || true)"
    if grep -q '^passwordauthentication no$' <<<"$ssh_settings"; then ui_check pass "SSH 密码登录已禁用"; else ui_check warn "SSH 仍允许密码登录"; fi
    if grep -Eq '^permitrootlogin (no|prohibit-password)$' <<<"$ssh_settings"; then ui_check pass "root 登录已限制"; else ui_check warn "root 可直接通过 SSH 登录"; fi
    ui_kv "SSH 端口" "$(awk '/^port /{print $2;exit}' <<<"$ssh_settings")"
  else
    ui_check warn "无法检查 sshd 有效配置"
  fi
  uid0_count="$(awk -F: '$3==0{count++}END{print count+0}' /etc/passwd)"
  if [[ "$uid0_count" -eq 1 ]]; then ui_check pass "只有一个 UID 0 账户"; else ui_check warn "检测到 $uid0_count 个 UID 0 账户"; fi
  if command_exists fail2ban-client && fail2ban-client ping >/dev/null 2>&1; then
    ui_check pass "Fail2ban 正在运行"
  else
    ui_check warn "Fail2ban 未安装或未运行"
  fi
  if [[ -f /var/run/reboot-required ]]; then ui_check warn "系统提示需要重启"; else ui_check pass "没有待处理的重启提示"; fi
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

security_fail2ban_jails() {
  fail2ban-client status 2>/dev/null |
    sed -n 's/.*Jail list:[[:space:]]*//p' |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d'
}

security_fail2ban_total_banned() {
  local jails="${1:-}" jail count total=0
  while IFS= read -r jail; do
    [[ -n "$jail" ]] || continue
    count="$(fail2ban-client status "$jail" 2>/dev/null | awk -F: '/Currently banned/{gsub(/[[:space:]]/,"",$2);print $2;exit}')"
    [[ "$count" =~ ^[0-9]+$ ]] && total=$((total + count))
  done <<<"$jails"
  printf '%s' "$total"
}

security_fail2ban_jail_manage() {
  local jails jail action banned
  jails="$(security_fail2ban_jails || true)"
  [[ -n "$jails" ]] || { warn "当前没有启用的 Jail。"; return 1; }
  ui_page "Fail2ban / Jail" "选择 Jail 查看封禁状态与解除误封"
  while IFS= read -r jail; do
    printf '  %b•%b %s\n' "$CYAN" "$NC" "$jail"
  done <<<"$jails"
  jail="$(read_input "Jail 名称" "")"
  grep -Fxq "$jail" <<<"$jails" || { warn "Jail 不存在或当前未启用：$jail"; return 1; }
  while true; do
    ui_page "Fail2ban / $jail" "实时封禁统计、IP 清单与误封处理"
    fail2ban-client status "$jail" 2>/dev/null | sed -n '1,16p'
    banned="$(fail2ban-client status "$jail" 2>/dev/null | sed -n 's/.*Banned IP list:[[:space:]]*//p')"
    ui_section "操作" "accent"
    ui_action 1 "解除一个 IP 的封禁" "warning"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1)
        local address
        [[ -n "$banned" ]] || { warn "当前 Jail 没有封禁 IP。"; pause; continue; }
        address="$(read_input "待解除的 IP" "")"
        valid_firewall_source "$address" && [[ "$address" != "any" && "$address" != */* ]] || {
          warn "IP 地址格式无效。"
          pause
          continue
        }
        tr ' ' '\n' <<<"$banned" | grep -Fxq "$address" || {
          warn "$address 不在当前封禁清单中。"
          pause
          continue
        }
        confirm "从 $jail 解除 $address 的封禁？" || continue
        require_root
        run fail2ban-client set "$jail" unbanip "$address"
        audit "action=fail2ban-unban jail=$jail address=$address"
        ui_success "已提交解除封禁操作"
        pause
        ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

security_fail2ban_reload() {
  confirm "重新加载 Fail2ban 配置？" || return 0
  require_root
  run fail2ban-client reload
  if [[ "$DRY_RUN" -eq 0 ]]; then
    fail2ban-client ping >/dev/null 2>&1 || { warn "重新加载后 Fail2ban 无法响应。"; return 1; }
  fi
  audit "action=fail2ban-reload"
  ui_success "Fail2ban 配置已重新加载"
}

security_fail2ban() {
  local action state enabled version jails jail_count banned style client_ready
  while true; do
    if ! command_exists fail2ban-client; then
      ui_page "Fail2ban 管理" "安装登录防护并管理服务生命周期"
      ui_panel_begin "组件状态"
      ui_panel_kv "安装状态" "未安装" "$YELLOW"
      ui_panel_end
      ui_section "操作" "accent"
      ui_action 1 "安装 Fail2ban" "success" "通过软件目录安装单个系统包"
      ui_action 0 "返回" "muted"
      action="$(read_input "请选择" "0")"
      case "$action" in
        1) catalog_install fail2ban || true; pause ;;
        0) return 0 ;;
        *) warn "未知选项" ;;
      esac
      continue
    fi

    state="$(service_state fail2ban.service)"
    enabled="$(systemctl is-enabled fail2ban.service 2>/dev/null || true)"
    enabled="${enabled:-disabled}"
    version="$(fail2ban-client --version 2>/dev/null | head -n 1 || true)"
    jails=""
    jail_count=0
    banned=0
    client_ready=0
    if [[ "$state" == "active" ]]; then
      style="$GREEN"
      if fail2ban-client ping >/dev/null 2>&1; then
        client_ready=1
        jails="$(security_fail2ban_jails || true)"
        jail_count="$(grep -c . <<<"$jails" || true)"
        banned="$(security_fail2ban_total_banned "$jails")"
      else
        jail_count="不可读取"
        banned="不可读取"
      fi
    else
      style="$YELLOW"
    fi

    ui_page "Fail2ban 管理" "服务、Jail、日志与误封处理"
    ui_panel_begin "运行状态"
    ui_panel_kv "状态" "● $state" "$style"
    ui_panel_kv "开机启动" "$enabled"
    ui_panel_kv "版本" "${version:-未知}"
    ui_panel_kv "启用 Jail" "$jail_count"
    ui_panel_kv "当前封禁" "$banned"
    ui_panel_end
    if [[ "$state" == "active" && "$client_ready" -eq 0 ]]; then
      ui_note "服务正在运行，但当前用户无法读取 Fail2ban Socket；请使用 sudo serverctl。"
    fi
    ui_section "观察与处置" "primary"
    ui_action 1 "查看全部 Jail" "action"
    ui_action 2 "管理一个 Jail" "action" "查看详情并解除误封 IP"
    ui_action 3 "查看服务日志" "action"
    ui_action 4 "重新加载配置" "warning"
    ui_section "服务生命周期" "accent"
    if [[ "$state" == "active" ]]; then
      ui_action 5 "启动服务" "muted" "当前已经运行"
      ui_action 6 "停止服务" "danger"
      ui_action 7 "重启服务" "warning"
    else
      ui_action 5 "启动服务" "success"
      ui_action 6 "停止服务" "muted" "当前未运行"
      ui_action 7 "重启服务" "warning"
    fi
    if [[ "$enabled" == "enabled" ]]; then
      ui_action 8 "启用开机启动" "muted" "当前已经启用"
      ui_action 9 "禁用开机启动" "danger"
    else
      ui_action 8 "启用开机启动" "success"
      ui_action 9 "禁用开机启动" "muted" "当前未启用"
    fi
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1)
        ui_page "Fail2ban Jail" "全部已启用 Jail 的封禁统计"
        if [[ "$client_ready" -eq 1 && -n "$jails" ]]; then
          local jail
          while IFS= read -r jail; do
            fail2ban-client status "$jail" 2>/dev/null | sed -n '1,12p'
            printf '\n'
          done <<<"$jails"
        else
          ui_empty "服务未运行或没有启用的 Jail"
        fi
        pause
        ;;
      2)
        if [[ "$client_ready" -eq 1 ]]; then security_fail2ban_jail_manage || true; else warn "Fail2ban 未运行或当前用户无权读取。"; fi
        pause
        ;;
      3) services_logs fail2ban.service; pause ;;
      4)
        if [[ "$state" == "active" ]]; then security_fail2ban_reload || true; else warn "请先启动 Fail2ban。"; fi
        pause
        ;;
      5) services_apply_action fail2ban.service start || true; pause ;;
      6) services_apply_action fail2ban.service stop || true; pause ;;
      7) services_apply_action fail2ban.service restart || true; pause ;;
      8) services_apply_action fail2ban.service enable || true; pause ;;
      9) services_apply_action fail2ban.service disable || true; pause ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

security_certificate_days_left() {
  local not_after="$1" now="${2:-}" expiry_epoch delta
  [[ -n "$now" ]] || now="$(date +%s)"
  expiry_epoch="$(date -d "$not_after" +%s 2>/dev/null)" || return 1
  delta=$((expiry_epoch - now))
  if (( delta >= 0 )); then
    printf '%s' "$(((delta + 86399) / 86400))"
  else
    printf '%s' "$(((delta - 86399) / 86400))"
  fi
}

security_tls_inspect() {
  local target port endpoint pem certificate not_after days_left identity_check
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
  ui_section "有效期与身份" "accent"
  not_after="$(openssl x509 -noout -enddate 2>/dev/null <<<"$pem" | sed 's/^notAfter=//' || true)"
  if [[ -n "$not_after" ]] && days_left="$(security_certificate_days_left "$not_after")"; then
    if (( days_left < 0 )); then
      ui_check fail "证书已经过期 $((-days_left)) 天"
    elif (( days_left < 14 )); then
      ui_check fail "证书将在 $days_left 天内过期"
    elif (( days_left < 30 )); then
      ui_check warn "证书将在 $days_left 天后过期"
    else
      ui_check pass "证书剩余有效期 $days_left 天"
    fi
  else
    ui_check warn "无法计算证书剩余有效期"
  fi
  if [[ "$target" == *:* || "$target" =~ ^[0-9]+([.][0-9]+){3}$ ]]; then
    identity_check="$(openssl x509 -noout -checkip "$target" 2>/dev/null <<<"$pem" || true)"
  else
    identity_check="$(openssl x509 -noout -checkhost "$target" 2>/dev/null <<<"$pem" || true)"
  fi
  if [[ "$identity_check" == *"does match certificate"* ]]; then
    ui_check pass "证书身份与 $target 匹配"
  else
    ui_check fail "证书身份与 $target 不匹配"
  fi
  ui_section "证书主机名" "primary"
  openssl x509 -noout -ext subjectAltName 2>/dev/null <<<"$pem" || true
}

security_enable_firewall() {
  local ssh_port raw old_ifs spec; local rules=()
  ssh_port="$(detect_ssh_port)"
  ui_page "启用基础防火墙" "保留当前 SSH 端口并应用默认入站策略"
  ui_panel_begin "变更摘要"
  ui_panel_kv "保留 SSH" "$ssh_port/tcp" "$GREEN"
  ui_panel_kv "默认入站" "拒绝"
  ui_panel_kv "默认出站" "允许"
  ui_panel_end
  ui_note "额外规则支持单端口或范围，例如 443/tcp、8443/udp、10000:10100/udp。"
  raw="$(read_input "额外规则（逗号分隔，可留空）" "")"
  if [[ -n "$raw" ]]; then
    old_ifs="$IFS"
    IFS=',' read -r -a rules <<<"${raw// /}"
    IFS="$old_ifs"
    for spec in "${rules[@]}"; do
      valid_firewall_rule_spec "$spec" || { warn "无效防火墙规则：$spec"; return 1; }
    done
  fi
  confirm "安装并启用 UFW？" || return 0
  require_root
  package_install ufw
  run ufw allow "$ssh_port/tcp"
  for spec in "${rules[@]}"; do
    [[ "$spec" == */* ]] || spec="$spec/tcp"
    run ufw allow "$spec"
  done
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw --force enable
  audit "action=firewall-enable ssh_port=$ssh_port extra=${raw:-none}"
  ui_success "UFW 已启用，并保留 SSH 端口 $ssh_port/tcp"
}

security_firewall_rule() {
  local ports protocol_choice protocol_label source protocol
  local protocols=()
  command_exists ufw || { warn "请先安装 UFW。"; return 1; }
  ui_page "添加 UFW 规则" "支持 TCP、UDP、端口范围和来源限制"
  ports="$(read_input "端口或范围" "443")"
  valid_port_range "$ports" || { warn "端口格式无效。"; return 1; }
  ui_action 1 "TCP" "action"
  ui_action 2 "UDP" "action"
  ui_action 3 "TCP + UDP" "warning"
  protocol_choice="$(read_input "协议" "1")"
  case "$protocol_choice" in
    1) protocols=(tcp); protocol_label="TCP" ;;
    2) protocols=(udp); protocol_label="UDP" ;;
    3) protocols=(tcp udp); protocol_label="TCP + UDP" ;;
    *) warn "协议选项无效。"; return 1 ;;
  esac
  source="$(read_input "来源 IP/CIDR；any 表示任意来源" "any")"
  valid_firewall_source "$source" || { warn "来源 IP 或 CIDR 格式无效。"; return 1; }
  ui_section "规则预览" "accent"
  ui_kv "端口" "$ports"
  ui_kv "协议" "$protocol_label"
  ui_kv "来源" "$source"
  confirm "添加以上放行规则？" || return 0
  require_root
  for protocol in "${protocols[@]}"; do
    if [[ "$source" == "any" ]]; then
      run ufw allow "$ports/$protocol"
    else
      run ufw allow from "$source" to any port "$ports" proto "$protocol"
    fi
  done
  audit "action=firewall-rule-add ports=$ports protocol_choice=$protocol_choice source=$source"
  ui_success "UFW 放行规则已添加"
}

security_firewall_delete_rule() {
  local rules number
  command_exists ufw || { warn "请先安装 UFW。"; return 1; }
  ui_page "删除 UFW 规则" "按编号精确删除，避免协议或来源匹配歧义"
  rules="$(ufw status numbered 2>/dev/null || true)"
  printf '%s\n' "$rules"
  grep -q '^\[' <<<"$rules" || grep -q '^[[:space:]]*\[' <<<"$rules" || {
    ui_empty "当前没有可删除的编号规则"
    return 0
  }
  number="$(read_input "规则编号" "")"
  [[ "$number" =~ ^[0-9]+$ ]] || { warn "规则编号无效。"; return 1; }
  grep -Eq "^[[:space:]]*\\[[[:space:]]*$number\\]" <<<"$rules" || {
    warn "没有找到编号为 $number 的规则。"
    return 1
  }
  confirm "删除 UFW 规则 [$number]？" || return 0
  require_root
  run ufw --force delete "$number"
  audit "action=firewall-rule-delete number=$number"
  ui_success "UFW 规则 [$number] 已删除"
}

security_firewall_disable() {
  ui_danger "禁用 UFW 会撤销主机层入站保护，但不会删除现有规则。"
  confirm "确认禁用 UFW？" || return 0
  require_root
  run ufw disable
  audit "action=firewall-disable"
  ui_success "UFW 已禁用，现有规则仍被保留"
}

security_firewall_reload() {
  platform_firewall_active || { warn "UFW 当前未启用。"; return 1; }
  confirm "重新加载 UFW 规则？" || return 0
  require_root
  run ufw reload
  audit "action=firewall-reload"
  ui_success "UFW 规则已重新加载"
}

security_firewall_logging() {
  local choice level
  command_exists ufw || { warn "请先安装 UFW。"; return 1; }
  ui_page "UFW 日志" "调整防火墙事件记录级别"
  ui_action 1 "关闭日志" "muted"
  ui_action 2 "低级别" "success" "适合日常运行"
  ui_action 3 "中级别" "warning"
  choice="$(read_input "请选择" "2")"
  case "$choice" in
    1) level=off ;;
    2) level=low ;;
    3) level=medium ;;
    *) warn "日志级别选项无效。"; return 1 ;;
  esac
  confirm "将 UFW 日志级别设置为 $level？" || return 0
  require_root
  run ufw logging "$level"
  audit "action=firewall-logging level=$level"
  ui_success "UFW 日志级别已设置为 $level"
}

security_firewall_manage() {
  local action state defaults logging state_style
  while true; do
    if command_exists ufw; then
      if platform_firewall_active; then state="active"; state_style="$GREEN"; else state="inactive"; state_style="$YELLOW"; fi
      defaults="$(ufw status verbose 2>/dev/null | awk -F': ' '/^Default:/{print $2;exit}')"
      logging="$(ufw status verbose 2>/dev/null | awk -F': ' '/^Logging:/{print $2;exit}')"
    else
      state="未安装"
      state_style="$YELLOW"
      defaults="—"
      logging="—"
    fi
    ui_page "UFW 防火墙管理" "状态、规则、协议、来源限制与日志"
    ui_panel_begin "防火墙状态"
    ui_panel_kv "状态" "● $state" "$state_style"
    ui_panel_kv "默认策略" "${defaults:-未知}"
    ui_panel_kv "日志" "${logging:-未知}"
    ui_panel_kv "SSH 端口" "$(detect_ssh_port)/tcp"
    ui_panel_end
    ui_section "规则" "primary"
    ui_action 1 "查看完整状态" "action"
    ui_action 2 "添加放行规则" "success" "TCP、UDP、范围与来源 IP"
    ui_action 3 "删除编号规则" "danger"
    ui_section "运行控制" "accent"
    if [[ "$state" == "active" ]]; then
      ui_action 4 "启用基础防火墙" "muted" "当前已经启用"
      ui_action 5 "禁用防火墙" "danger"
      ui_action 6 "重新加载规则" "warning"
    else
      ui_action 4 "启用基础防火墙" "success" "自动保留当前 SSH 端口"
      ui_action 5 "禁用防火墙" "muted" "当前未启用"
      ui_action 6 "重新加载规则" "muted" "启用后可用"
    fi
    ui_action 7 "调整日志级别" "action"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) security_firewall_status || true; pause ;;
      2) security_firewall_rule || true; pause ;;
      3) security_firewall_delete_rule || true; pause ;;
      4) security_enable_firewall || true; pause ;;
      5)
        if [[ "$state" == "active" ]]; then security_firewall_disable || true; else warn "UFW 当前未启用。"; fi
        pause
        ;;
      6) security_firewall_reload || true; pause ;;
      7) security_firewall_logging || true; pause ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
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
    ui_page "安全中心" "评估暴露面并控制防火墙、SSH 与登录防护"
    ui_section "评估与观察" "primary"
    ui_item 1 "安全基线检查" "防火墙、SSH、UID 0、Fail2ban 与重启"
    ui_item 2 "公网监听端口" "识别监听所有地址的服务"
    ui_section "主机防护" "accent"
    ui_item 3 "UFW 防火墙管理" "启停、TCP/UDP、端口范围、来源与日志"
    ui_item 4 "SSH 安全向导" "端口、公钥、密码与 root 登录策略"
    ui_item 5 "Fail2ban 管理" "服务启停、Jail、日志与解除误封"
    ui_section "事件与证书" "primary"
    ui_item 6 "SSH 登录事件"
    ui_item 7 "TLS 证书检查" "签发者、有效期、指纹与主机名"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) security_audit ;;
      2) security_exposed_ports || true ;;
      3) security_firewall_manage ;;
      4) security_configure_ssh || true ;;
      5) security_fail2ban || true ;;
      6) security_auth_log ;;
      7) security_tls_inspect || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
