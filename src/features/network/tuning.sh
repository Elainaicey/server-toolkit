#!/usr/bin/env bash

network_enable_bbr() {
  local available current
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')"
  ui_page "启用 BBR" "检查内核能力并写入独立 sysctl 配置"
  [[ "$available" == *bbr* ]] || warn "将尝试加载 BBR 内核模块。"
  confirm "启用 BBR 拥塞控制？" || return 0; require_root
  if [[ "$available" != *bbr* ]] && command_exists modprobe; then
    run modprobe tcp_bbr || true
    if [[ "$DRY_RUN" -ne 1 ]]; then
      available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    fi
  fi
  [[ "$DRY_RUN" -eq 1 || "$available" == *bbr* ]] || { warn "当前内核无法启用 BBR。"; return 1; }
  local config=/etc/sysctl.d/98-server-toolkit-bbr.conf temporary=""
  backup_file "$config" || { warn "无法备份 BBR 配置。"; return 1; }
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将写入 $config。"; else
    temporary="$(mktemp)" || { warn "无法创建 BBR 配置临时文件。"; return 1; }
    if ! {
      printf '# Managed by Server Toolkit\n'
      printf '# Previous: %s\n' "$current"
      printf 'net.core.default_qdisc = fq\n'
      printf 'net.ipv4.tcp_congestion_control = bbr\n'
    } >"$temporary"; then
      rm -f "$temporary"
      warn "无法生成 BBR 配置。"
      return 1
    fi
    install -m 0644 "$temporary" "$config" || { rm -f "$temporary"; warn "无法安装 BBR 配置。"; return 1; }
    rm -f "$temporary"
  fi
  run sysctl --system || { warn "应用 sysctl 配置失败。"; return 1; }
  if [[ "$DRY_RUN" -eq 0 && "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" != "bbr" ]]; then
    warn "应用配置后拥塞控制算法仍不是 BBR。"
    return 1
  fi
  audit "action=enable-bbr previous=$current"
  ui_success "BBR 已启用"
}

network_restore_bbr() {
  local config=/etc/sysctl.d/98-server-toolkit-bbr.conf available previous fallback=""
  [[ -f "$config" ]] || { warn "没有检测到 Server Toolkit 管理的 BBR 配置。"; return 1; }
  grep -Fq '# Managed by Server Toolkit' "$config" || {
    warn "$config 不属于 Server Toolkit，拒绝删除。"
    return 1
  }
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  previous="$(sed -n 's/^# Previous: //p' "$config" | head -n 1)"
  if [[ -n "$previous" && " $available " == *" $previous "* ]]; then
    fallback="$previous"
  elif [[ " $available " == *" cubic "* ]]; then
    fallback=cubic
  elif [[ " $available " == *" reno "* ]]; then
    fallback=reno
  else
    fallback="$(awk '{print $1}' <<<"$available")"
  fi
  [[ -n "$fallback" ]] || { warn "无法确定可用的拥塞控制算法。"; return 1; }
  ui_danger "将删除工具管理的 BBR 持久化配置，并把当前算法切换为 $fallback。"
  confirm "恢复系统拥塞控制设置？" || return 0
  require_root
  backup_file "$config" || { warn "无法备份 BBR 配置。"; return 1; }
  run rm -f -- "$config" || { warn "无法移除托管 BBR 配置。"; return 1; }
  run sysctl -w "net.ipv4.tcp_congestion_control=$fallback" || {
    warn "无法切换拥塞控制算法；原配置已保存在项目备份中。"
    return 1
  }
  if [[ "$DRY_RUN" -eq 0 && "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" != "$fallback" ]]; then
    warn "当前拥塞控制算法未切换到 $fallback。"
    return 1
  fi
  audit "action=restore-congestion-control value=$fallback"
  ui_success "已移除托管 BBR 配置，当前算法为 $fallback"
}

network_bbr_manage() {
  local current available managed="否" action
  current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')"
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf '未知')"
  if [[ -f /etc/sysctl.d/98-server-toolkit-bbr.conf ]] &&
    grep -Fq '# Managed by Server Toolkit' /etc/sysctl.d/98-server-toolkit-bbr.conf; then
    managed="是"
  fi
  ui_page "BBR 拥塞控制" "查看内核能力、启用 BBR 或恢复托管配置"
  ui_panel_begin "当前状态"
  if [[ "$current" == "bbr" ]]; then ui_panel_kv "当前算法" "● bbr" "$GREEN"; else ui_panel_kv "当前算法" "● $current" "$YELLOW"; fi
  ui_panel_kv "可用算法" "$available"
  ui_panel_kv "工具托管" "$managed"
  ui_panel_end
  ui_section "操作" "accent"
  ui_action 1 "启用 BBR" "success"
  if [[ "$managed" == "是" ]]; then
    ui_action 2 "恢复系统设置" "warning" "移除工具管理的持久化配置"
  else
    ui_action 2 "恢复系统设置" "muted" "没有工具管理的配置"
  fi
  ui_action 0 "返回" "muted"
  action="$(read_input "请选择" "0")"
  case "$action" in
    1) network_enable_bbr ;;
    2) network_restore_bbr ;;
    0) return 0 ;;
    *) warn "未知选项"; return 1 ;;
  esac
}

network_set_address_preference() {
  ui_page "IP 地址优先级" "设置 IPv4 优先或恢复系统默认地址选择"
  ui_action 1 "IPv4 优先" "action"
  ui_action 2 "恢复系统默认" "warning"
  ui_action 0 "取消" "muted"
  local choice action="恢复系统默认地址选择"
  choice="$(read_input "请选择" "0")"
  [[ "$choice" == "1" || "$choice" == "2" ]] || return 0
  if [[ "$choice" == "1" ]]; then
    action="设置 IPv4 优先"
  fi
  confirm "$action？" || return 0
  require_root
  local config=/etc/gai.conf temporary=""
  backup_file "$config" || { warn "无法备份 $config。"; return 1; }
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将更新 $config。"; return 0; fi
  temporary="$(mktemp)" || { warn "无法创建地址优先级临时文件。"; return 1; }
  if [[ -f "$config" ]]; then
    awk '
      $0 == "# BEGIN Server Toolkit" {managed=1; next}
      $0 == "# END Server Toolkit" && managed {managed=0; next}
      !managed {print}
    ' "$config" >"$temporary" || { rm -f "$temporary"; warn "无法读取 $config。"; return 1; }
  fi
  if [[ "$choice" == "1" ]]; then
    cat >>"$temporary" <<'EOF'

# BEGIN Server Toolkit
precedence ::ffff:0:0/96 100
# END Server Toolkit
EOF
  fi
  install -m 0644 "$temporary" "$config" || { rm -f "$temporary"; warn "无法更新 $config。"; return 1; }
  rm -f "$temporary"
  if [[ "$choice" == "1" ]]; then
    grep -Fqx 'precedence ::ffff:0:0/96 100' "$config" || { warn "IPv4 优先级写入后验证失败。"; return 1; }
  elif grep -Fq '# BEGIN Server Toolkit' "$config"; then
    warn "托管的地址优先级配置未完全移除。"
    return 1
  fi
  audit "action=set-address-preference mode=$choice"
  ui_success "$action 完成"
}
