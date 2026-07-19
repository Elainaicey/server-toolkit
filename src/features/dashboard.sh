#!/usr/bin/env bash

dashboard_show() {
  platform_detect
  local failed_units running_services listeners upgrades docker_state="未安装" containers="-" root_total root_used
  failed_units="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
  running_services="$(systemctl --type=service --state=running --no-legend 2>/dev/null | grep -c . || true)"
  listeners="0"
  if command_exists ss; then listeners="$(ss -H -ltn 2>/dev/null | wc -l | tr -d ' ' || true)"; fi
  upgrades="$(package_upgradable_count)"
  if command_exists docker; then
    docker_state="$(service_state docker.service)"
    containers="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ' || true) 个运行中"
  fi
  root_total="$(df -Pm / 2>/dev/null | awk 'NR==2{print $2}')"
  root_used="$(df -Pm / 2>/dev/null | awk 'NR==2{print $3}')"

  ui_page "系统仪表盘" "实时概览 · $(date '+%Y-%m-%d %H:%M:%S')"
  ui_section "主机"
  ui_kv "系统" "$OS_NAME"
  ui_kv "环境" "$ARCH · $VIRTUALIZATION"
  ui_kv "运行时间" "$UPTIME_TEXT"
  ui_kv "系统负载" "$LOAD_AVERAGE"
  ui_kv "处理器" "$CPU_CORES vCPU"

  ui_section "资源"
  ui_progress "内存" "$MEMORY_USED_MB" "$MEMORY_MB" "MiB"
  if [[ "$SWAP_MB" =~ ^[0-9]+$ ]] && (( SWAP_MB > 0 )); then
    ui_progress "Swap" "$SWAP_USED_MB" "$SWAP_MB" "MiB"
  else
    ui_status "Swap" "未配置" "warn"
  fi
  ui_progress "根分区" "${root_used:-0}" "${root_total:-0}" "MiB"

  ui_section "运行状态"
  if (( failed_units > 0 )); then
    ui_status "systemd 服务" "$running_services 运行 · $failed_units 失败" "bad"
  else
    ui_status "systemd 服务" "$running_services 运行 · 0 失败" "good"
  fi
  ui_kv "TCP 监听" "$listeners"
  if (( upgrades > 0 )); then ui_status "可更新软件" "$upgrades" "warn"; else ui_status "可更新软件" "0" "good"; fi
  if [[ "$docker_state" == "active" ]]; then ui_status "Docker" "$docker_state · $containers" "good"; else ui_kv "Docker" "$docker_state · $containers"; fi

  if [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB < 512 )) && [[ "$SWAP_MB" == "0" ]]; then
    ui_note "内存较小且没有 Swap，可在系统管理中创建。"
  fi
}
