#!/usr/bin/env bash

network_show() {
  print_title "网络检测"
  ip -brief address 2>/dev/null || true
  printf '\n默认路由：\n'
  ip route show default 2>/dev/null || true
  ip -6 route show default 2>/dev/null || true
  printf '\nDNS：\n'
  sed -n '1,20p' /etc/resolv.conf 2>/dev/null || true
  printf '\nTCP 拥塞控制：\n'
  sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control 2>/dev/null || true
}

network_remove_gai_block() {
  [[ -f /etc/gai.conf ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 从 /etc/gai.conf 移除 Server Toolkit 配置块"
  else
    sed -i '/# BEGIN Server Toolkit gai/,/# END Server Toolkit gai/d' /etc/gai.conf
  fi
}

network_set_ip_preference() {
  local mode="$1"
  backup_file /etc/gai.conf
  [[ -f /etc/gai.conf ]] || { [[ "$DRY_RUN" -eq 1 ]] || touch /etc/gai.conf; }
  network_remove_gai_block
  case "$mode" in
    ipv4)
      log_step "设置 IPv4 优先"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY-RUN] 追加 IPv4 优先配置块"
      else
        cat >> /etc/gai.conf <<'GAI'
# BEGIN Server Toolkit gai
precedence ::ffff:0:0/96 100
# END Server Toolkit gai
GAI
      fi
      ;;
    ipv6|auto)
      log_step "使用系统默认 IPv6/自动地址选择"
      ;;
    *) log_warn "未知 IP 优先级模式：$mode" ;;
  esac
}

network_enable_bbr() {
  log_step "启用 BBR"
  local available
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  [[ "$available" == *bbr* ]] || log_warn "当前内核未显示支持 BBR：${available:-未知}"
  backup_file /etc/sysctl.d/98-server-toolkit-bbr.conf
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 写入 /etc/sysctl.d/98-server-toolkit-bbr.conf"
  else
    cat > /etc/sysctl.d/98-server-toolkit-bbr.conf <<'SYSCTL'
# Managed by Server Toolkit
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL
  fi
  run sysctl --system
}

network_apply_tcp_profile() {
  local profile="$1"
  local conf="/etc/sysctl.d/97-server-toolkit-tcp.conf"
  backup_file "$conf"
  log_step "应用 TCP 优化档位：$profile"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 写入 $conf"
    return 0
  fi
  case "$profile" in
    normal)
      cat > "$conf" <<'SYSCTL'
# Managed by Server Toolkit: normal
net.ipv4.tcp_fastopen = 3
SYSCTL
      ;;
    proxy)
      cat > "$conf" <<'SYSCTL'
# Managed by Server Toolkit: proxy
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
SYSCTL
      ;;
    high)
      cat > "$conf" <<'SYSCTL'
# Managed by Server Toolkit: high
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 16384
net.core.netdev_max_backlog = 16384
SYSCTL
      ;;
    none) rm -f "$conf" ;;
    *) log_warn "未知 TCP 优化档位：$profile"; return 0 ;;
  esac
  run sysctl --system
}

network_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    ui_panel_start "网络 / IPv6 / BBR"
    ui_panel_line "$(printf '%bIPv4%b  %s    %bIPv6%b  %s    %bGitHub%b  %s' "$DIM" "$NC" "$(status_word "${HAS_IPV4:-0}")" "$DIM" "$NC" "$(status_word "${HAS_IPV6:-0}")" "$DIM" "$NC" "$(status_word "${GITHUB_OK:-0}")")"
    ui_panel_rule
    ui_panel_line "[01] 查看网络详情"
    ui_panel_line "[02] 设置 IPv4 优先"
    ui_panel_line "[03] 设置 IPv6/系统默认优先"
    ui_panel_line "[04] 启用 BBR"
    ui_panel_line "[05] TCP 档位：普通服务器"
    ui_panel_line "[06] TCP 档位：代理节点"
    ui_panel_line "[07] TCP 档位：高并发节点"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) network_show; pause ;;
      2|02) network_set_ip_preference ipv4; pause ;;
      3|03) network_set_ip_preference ipv6; pause ;;
      4|04) network_enable_bbr; pause ;;
      5|05) network_apply_tcp_profile normal; pause ;;
      6|06) network_apply_tcp_profile proxy; pause ;;
      7|07) network_apply_tcp_profile high; pause ;;
      0|00) break ;;
      *) log_warn "未知选项"; pause ;;
    esac
  done
}
