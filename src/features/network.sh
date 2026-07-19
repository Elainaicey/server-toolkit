#!/usr/bin/env bash

network_show() {
  ui_header "网络概览"
  ip -brief address 2>/dev/null || true
  ui_section "默认路由"; ip route show default 2>/dev/null || true; ip -6 route show default 2>/dev/null || true
  ui_section "DNS"; sed -n '1,12p' /etc/resolv.conf 2>/dev/null || true
  ui_section "拥塞控制"; sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control 2>/dev/null || true
}

network_connectivity_test() {
  ui_header "连通性检查"
  if getent hosts github.com >/dev/null 2>&1; then doctor_result pass "DNS 解析 github.com"; else doctor_result fail "DNS 解析失败"; fi
  if ip -4 route get 1.1.1.1 >/dev/null 2>&1; then doctor_result pass "IPv4 默认路由"; else doctor_result warn "没有 IPv4 默认路由"; fi
  if ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1; then doctor_result pass "IPv6 默认路由"; else doctor_result warn "没有 IPv6 默认路由"; fi
  if command_exists curl; then
    if curl -4fsI --connect-timeout 3 --max-time 8 https://github.com >/dev/null 2>&1; then doctor_result pass "IPv4 HTTPS"; else doctor_result warn "IPv4 HTTPS 不可用"; fi
    if curl -6fsI --connect-timeout 3 --max-time 8 https://github.com >/dev/null 2>&1; then doctor_result pass "IPv6 HTTPS"; else doctor_result warn "IPv6 HTTPS 不可用"; fi
  else
    doctor_result warn "未安装 curl，跳过 HTTPS 检查"
  fi
}

network_list_ports() {
  ui_header "监听端口"
  if command_exists ss; then
    printf '%-8s %-24s %s\n' "协议" "本地地址" "进程"
    ss -H -lntup 2>/dev/null | awk '{printf "%-8s %-24s %s\n", $1, $5, substr($0,index($0,$7))}'
  else
    warn "缺少 ss 命令。"
  fi
}

network_port_detail() {
  local port; port="$(read_input "端口" "80")"; valid_port "$port" || { warn "端口无效。"; return 1; }
  ui_header "端口 $port"
  ss -H -lntup "sport = :$port" 2>/dev/null || true
  if command_exists lsof; then
    lsof -nP -i ":$port" 2>/dev/null || true
  fi
}

network_enable_bbr() {
  local available; available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  [[ "$available" == *bbr* ]] || warn "将尝试加载 BBR 内核模块。"
  confirm "启用 BBR 拥塞控制？" || return 0; require_root
  if [[ "$available" != *bbr* ]] && command_exists modprobe; then
    run modprobe tcp_bbr || true
    if [[ "$DRY_RUN" -ne 1 ]]; then
      available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    fi
  fi
  [[ "$DRY_RUN" -eq 1 || "$available" == *bbr* ]] || { warn "当前内核无法启用 BBR。"; return 1; }
  local config=/etc/sysctl.d/98-server-toolkit-bbr.conf; backup_file "$config"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将写入 $config。"; else cat >"$config" <<'EOF'
# Managed by Server Toolkit
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  fi
  run sysctl --system; audit "action=enable-bbr"
}

network_set_address_preference() {
  ui_header "IP 地址优先级"
  ui_item 1 "IPv4 优先"
  ui_item 2 "恢复系统默认"
  ui_item 0 "取消"
  local choice action="恢复系统默认地址选择"
  choice="$(read_input "请选择" "0")"
  [[ "$choice" == "1" || "$choice" == "2" ]] || return 0
  if [[ "$choice" == "1" ]]; then
    action="设置 IPv4 优先"
  fi
  confirm "$action？" || return 0
  require_root
  local config=/etc/gai.conf; backup_file "$config"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将更新 $config。"; return 0; fi
  [[ -f "$config" ]] || touch "$config"
  sed -i '/# BEGIN Server Toolkit/,/# END Server Toolkit/d' "$config"
  if [[ "$choice" == "1" ]]; then
    cat >>"$config" <<'EOF'

# BEGIN Server Toolkit
precedence ::ffff:0:0/96 100
# END Server Toolkit
EOF
  fi
  audit "action=set-address-preference mode=$choice"
}

network_menu() {
  local choice
  while true; do
    ui_clear
    ui_header "网络与端口"
    ui_item 1 "网络概览"
    ui_item 2 "连通性检查"
    ui_item 3 "监听端口"
    ui_item 4 "查询端口"
    ui_item 5 "启用 BBR"
    ui_item 6 "IP 地址优先级"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) network_show ;;
      2) network_connectivity_test ;;
      3) network_list_ports ;;
      4) network_port_detail || true ;;
      5) network_enable_bbr || true ;;
      6) network_set_address_preference || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
