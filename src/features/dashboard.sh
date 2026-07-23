#!/usr/bin/env bash

dashboard_show() {
  platform_detect
  local failed_units running_services listeners upgrades docker_state="未安装" containers="-" root_total root_used
  local firewall_state="未启用" fail2ban_state="未安装" time_sync="未同步"
  failed_units="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
  running_services="$(systemctl --type=service --state=running --no-legend 2>/dev/null | grep -c . || true)"
  listeners="0"
  if command_exists ss; then listeners="$(ss -H -ltn 2>/dev/null | wc -l | tr -d ' ' || true)"; fi
  upgrades="$(package_upgradable_count)"
  if command_exists docker; then
    docker_state="$(service_state docker.service)"
    containers="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ' || true) 个运行中"
  fi
  if platform_firewall_active; then firewall_state="active"; fi
  if service_exists fail2ban.service; then fail2ban_state="$(service_state fail2ban.service)"; fi
  if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]; then time_sync="已同步"; fi
  root_total="$(df -Pm / 2>/dev/null | awk 'NR==2{print $2}')"
  root_used="$(df -Pm / 2>/dev/null | awk 'NR==2{print $3}')"

  ui_page "系统仪表盘" "实时概览 · $(date '+%Y-%m-%d %H:%M:%S')"
  ui_panel_begin "主机"
  ui_panel_kv "系统" "$OS_NAME"
  ui_panel_kv "环境" "$ARCH · $VIRTUALIZATION"
  ui_panel_kv "运行时间" "$UPTIME_TEXT"
  ui_panel_kv "系统负载" "$LOAD_AVERAGE"
  ui_panel_kv "处理器" "$CPU_CORES vCPU"
  ui_panel_end

  ui_section "资源" "primary"
  ui_progress "内存" "$MEMORY_USED_MB" "$MEMORY_MB" "MiB"
  if [[ "$SWAP_MB" =~ ^[0-9]+$ ]] && (( SWAP_MB > 0 )); then
    ui_progress "Swap" "$SWAP_USED_MB" "$SWAP_MB" "MiB"
  else
    ui_status "Swap" "未配置" "warn"
  fi
  ui_progress "根分区" "${root_used:-0}" "${root_total:-0}" "MiB"

  ui_section "运行状态" "accent"
  if (( failed_units > 0 )); then
    ui_status "systemd 服务" "$running_services 运行 · $failed_units 失败" "bad"
  else
    ui_status "systemd 服务" "$running_services 运行 · 0 失败" "good"
  fi
  ui_kv "TCP 监听" "$listeners"
  if (( upgrades > 0 )); then ui_status "可更新软件" "$upgrades" "warn"; else ui_status "可更新软件" "0" "good"; fi
  if [[ "$docker_state" == "active" ]]; then ui_status "Docker" "$docker_state · $containers" "good"; else ui_kv "Docker" "$docker_state · $containers"; fi

  ui_section "基础防护" "primary"
  if [[ "$firewall_state" == "active" ]]; then ui_status "UFW" "已启用" "good"; else ui_status "UFW" "$firewall_state" "warn"; fi
  if [[ "$fail2ban_state" == "active" ]]; then ui_status "Fail2ban" "运行中" "good"; else ui_status "Fail2ban" "$fail2ban_state" "warn"; fi
  if [[ "$time_sync" == "已同步" ]]; then ui_status "系统时间" "$time_sync" "good"; else ui_status "系统时间" "$time_sync" "warn"; fi

  if [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB < 512 )) && [[ "$SWAP_MB" == "0" ]]; then
    ui_note "内存较小且没有 Swap，可在系统管理中创建。"
  fi
}
