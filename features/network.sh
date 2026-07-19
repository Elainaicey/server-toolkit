#!/usr/bin/env bash

network_show() {
  ui_header "网络信息"
  ip -brief address 2>/dev/null || true
  printf '\n默认路由\n'
  ip route show default 2>/dev/null || true
  ip -6 route show default 2>/dev/null || true
  printf '\nDNS\n'
  sed -n '1,12p' /etc/resolv.conf 2>/dev/null || true
  printf '\n拥塞控制\n'
  sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control 2>/dev/null || true
}

network_enable_bbr() {
  local available
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  if [[ "$available" != *bbr* ]]; then
    warn "当前列表中没有 BBR，将尝试加载内核模块。"
  fi
  confirm "启用 BBR 拥塞控制？" || { warn "已取消。"; return 0; }
  require_root
  if [[ "$available" != *bbr* ]] && command_exists modprobe; then
    run modprobe tcp_bbr || true
    [[ "$DRY_RUN" -eq 1 ]] || available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  fi
  if [[ "$DRY_RUN" -ne 1 && "$available" != *bbr* ]]; then
    warn "当前内核不支持或无法加载 BBR，未修改配置。"
    return 1
  fi
  local config=/etc/sysctl.d/98-server-toolkit-bbr.conf
  backup_file "$config"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将写入 $config。"
  else
    cat >"$config" <<'EOF'
# Managed by Server Toolkit
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  fi
  run sysctl --system
}

network_set_address_preference() {
  ui_header "IP 地址优先级"
  ui_item 1 "IPv4 优先"
  ui_item 2 "恢复系统默认"
  ui_item 0 "取消"
  local choice
  choice="$(read_input "请选择" "0")"
  [[ "$choice" == "1" || "$choice" == "2" ]] || return 0
  local config=/etc/gai.conf
  local action="恢复系统默认地址选择"
  [[ "$choice" == "1" ]] && action="设置 IPv4 优先"
  confirm "$action？" || { warn "已取消。"; return 0; }
  require_root
  backup_file "$config"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将更新 $config。"
    return 0
  fi
  [[ -f "$config" ]] || touch "$config"
  sed -i '/# BEGIN Server Toolkit/,/# END Server Toolkit/d' "$config"
  if [[ "$choice" == "1" ]]; then
    cat >>"$config" <<'EOF'

# BEGIN Server Toolkit
precedence ::ffff:0:0/96 100
# END Server Toolkit
EOF
  fi
}
