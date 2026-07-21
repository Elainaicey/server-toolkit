#!/usr/bin/env bash

system_set_hostname() {
  local current name temporary
  ui_page "修改主机名" "验证格式、备份 hosts 并通过 hostnamectl 应用"
  current="$(hostname -s 2>/dev/null || hostname)"; name="$(read_input "新主机名" "$current")"
  [[ "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || { warn "主机名格式无效。"; return 1; }
  [[ "$name" != "$current" ]] || { info "主机名未变化。"; return 0; }
  confirm "将主机名从 $current 修改为 $name？" || return 0; require_root
  backup_file /etc/hostname; backup_file /etc/hosts; run hostnamectl set-hostname "$name"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将更新 /etc/hosts。"; return 0; fi
  temporary="$(mktemp)"
  awk -v name="$name" 'BEGIN{changed=0}$1=="127.0.1.1"{print "127.0.1.1 "name;changed=1;next}{print}END{if(!changed)print "127.0.1.1 "name}' /etc/hosts >"$temporary"
  install -m 0644 "$temporary" /etc/hosts; rm -f "$temporary"; audit "action=set-hostname value=$name"
}

system_set_timezone() {
  local current timezone
  ui_page "修改时区" "使用系统 zoneinfo 数据库配置时区"
  current="$(timedatectl show -p Timezone --value 2>/dev/null || printf 'Etc/UTC')"; timezone="$(read_input "时区" "$current")"
  [[ -f "/usr/share/zoneinfo/$timezone" ]] || { warn "不存在的时区：$timezone"; return 1; }
  [[ "$timezone" != "$current" ]] || { info "时区未变化。"; return 0; }
  confirm "将时区修改为 $timezone？" || return 0; require_root; backup_file /etc/timezone
  run timedatectl set-timezone "$timezone"; audit "action=set-timezone value=$timezone"
}

system_create_swap() {
  ui_page "创建 Swap" "为低内存 VPS 创建受保护的交换文件"
  swapon --show --noheadings 2>/dev/null | grep -q . && { warn "系统已经启用 Swap。"; return 0; }
  [[ ! -e /swapfile ]] || { warn "/swapfile 已存在。"; return 1; }
  local size_mb; size_mb="$(read_input "Swap 大小（MB）" "1024")"
  if [[ ! "$size_mb" =~ ^[0-9]+$ ]] || (( size_mb < 128 || size_mb > 32768 )); then
    warn "大小必须在 128-32768 MB。"
    return 1
  fi
  confirm "创建 ${size_mb} MB 的 /swapfile？" || return 0; require_root; backup_file /etc/fstab
  if command_exists fallocate; then run fallocate -l "${size_mb}M" /swapfile || run dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress; else run dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress; fi
  run chmod 600 /swapfile; run mkswap /swapfile; run swapon /swapfile
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将更新 /etc/fstab。"; else printf '/swapfile none swap sw 0 0\n' >>/etc/fstab; fi
  audit "action=create-swap size_mb=$size_mb"
}

system_time_sync() {
  ui_page "时间同步" "查看时间状态并启用 systemd NTP"
  timedatectl status 2>/dev/null | sed -n '1,10p' || true
  confirm "启用 systemd 时间同步？" || return 0; require_root; run timedatectl set-ntp true; audit "action=enable-time-sync"
}

system_cleanup() {
  ui_page "安全清理" "清理可再生成的缓存和过期 Journal"
  ui_kv "APT 缓存" "$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || printf '未知')"
  ui_kv "Journal" "$(journalctl --disk-usage 2>/dev/null | sed 's/.*take up //')"
  confirm "清理 APT 缓存并保留最近 14 天 Journal？" || return 0; require_root
  apt_run clean
  run journalctl --vacuum-time=14d
  audit "action=system-cleanup"
}
