#!/usr/bin/env bash

system_pressure() {
  platform_detect
  ui_page "资源压力分析" "负载、内存、存储空间、inode 与 OOM 事件的单次快照"
  local load_one memory_percent root_percent inode_percent oom_count
  load_one="$(awk '{print $1}' /proc/loadavg)"
  memory_percent=0
  if [[ "$MEMORY_USED_MB" =~ ^[0-9]+$ && "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB > 0 )); then
    memory_percent=$((MEMORY_USED_MB * 100 / MEMORY_MB))
  fi
  root_percent="${ROOT_USED_PERCENT:-0}"
  inode_percent="$(df -Pi / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')"
  oom_count="$(journalctl -k -b --no-pager 2>/dev/null | grep -Eic 'out of memory|oom-killer|killed process' || true)"

  ui_progress "内存压力" "$MEMORY_USED_MB" "$MEMORY_MB" "MiB"
  ui_kv "1 分钟负载" "$load_one / $CPU_CORES vCPU"
  ui_kv "根分区使用率" "${root_percent}%"
  ui_kv "根分区 inode" "${inode_percent:-0}%"
  ui_kv "本次启动 OOM" "$oom_count"

  ui_section "判断" "accent"
  if awk -v current_load="$load_one" -v cpu_count="$CPU_CORES" 'BEGIN{exit !(current_load > cpu_count)}'; then
    ui_check warn "负载已高于 CPU 核心数"
  else
    ui_check pass "当前负载处于可控范围"
  fi
  if (( memory_percent >= 90 )); then
    ui_check fail "内存使用率达到 ${memory_percent}%"
  elif (( memory_percent >= 75 )); then
    ui_check warn "内存使用率达到 ${memory_percent}%"
  else
    ui_check pass "内存余量正常"
  fi
  if [[ "$root_percent" =~ ^[0-9]+$ ]] && (( root_percent >= 90 )); then
    ui_check fail "根分区空间紧张"
  else
    ui_check pass "根分区空间正常"
  fi
  if [[ "$inode_percent" =~ ^[0-9]+$ ]] && (( inode_percent >= 90 )); then
    ui_check warn "inode 使用率较高"
  else
    ui_check pass "inode 余量正常"
  fi
  if (( oom_count > 0 )); then
    ui_check warn "本次启动检测到 $oom_count 条 OOM 相关日志"
  else
    ui_check pass "本次启动未检测到 OOM"
  fi
  ui_note "分析只在打开页面时运行一次，不会持续采样或启动监控。"
}

system_reboot_status() {
  ui_page "重启与内核状态" "内核版本、重启提示与最近启动记录"
  ui_panel_begin "当前状态"
  ui_panel_kv "运行内核" "$(uname -r)"
  if [[ -f /var/run/reboot-required ]]; then
    ui_panel_kv "重启需求" "● 系统提示需要重启" "$YELLOW"
  else
    ui_panel_kv "重启需求" "● 当前不需要" "$GREEN"
  fi
  ui_panel_end
  if [[ -r /var/run/reboot-required.pkgs ]]; then
    ui_section "触发重启提示的软件包" "accent"
    sed -n '1,30p' /var/run/reboot-required.pkgs
  fi
  ui_section "最近启动" "primary"
  journalctl --list-boots --no-pager 2>/dev/null | tail -n 8 || ui_empty "无法读取启动记录"
}
