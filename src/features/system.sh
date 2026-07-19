#!/usr/bin/env bash

system_overview() { dashboard_show; }

doctor_result() {
  case "$1" in
    pass) printf '  %b✓%b %s\n' "$GREEN" "$NC" "$2" ;;
    warn) printf '  %b!%b %s\n' "$YELLOW" "$NC" "$2" ;;
    fail) printf '  %b×%b %s\n' "$RED" "$NC" "$2" ;;
  esac
}

system_doctor() {
  platform_detect
  ui_header "环境检查"
  doctor_result pass "$OS_NAME ($ARCH)"
  if command_exists apt-get; then doctor_result pass "APT 可用"; else doctor_result fail "缺少 apt-get"; fi
  local audit; audit="$(dpkg --audit 2>/dev/null || true)"
  if [[ -z "$audit" ]]; then doctor_result pass "软件包状态正常"; else doctor_result fail "存在未完成的软件包配置"; fi
  local free_mb; free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"
  if [[ "$free_mb" =~ ^[0-9]+$ ]] && (( free_mb >= 512 )); then doctor_result pass "根分区可用 ${free_mb} MB"; else doctor_result warn "根分区剩余不足 512 MB"; fi
  if getent hosts deb.debian.org >/dev/null 2>&1; then doctor_result pass "DNS 解析正常"; else doctor_result fail "DNS 解析失败"; fi
  if command_exists curl && curl -fsI --connect-timeout 2 --max-time 5 https://github.com >/dev/null 2>&1; then doctor_result pass "HTTPS 与 GitHub 可用"; else doctor_result warn "未能访问 GitHub"; fi
  if [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB < 512 )) && [[ "$SWAP_MB" == "0" ]]; then doctor_result warn "低内存且没有 Swap"; else doctor_result pass "内存与 Swap 状态可用"; fi
  if command_exists systemctl; then
    doctor_result pass "systemd 可用"
  else
    doctor_result fail "systemd 不可用"
  fi
}

system_set_hostname() {
  local current name temporary
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
  current="$(timedatectl show -p Timezone --value 2>/dev/null || printf 'Etc/UTC')"; timezone="$(read_input "时区" "$current")"
  [[ -f "/usr/share/zoneinfo/$timezone" ]] || { warn "不存在的时区：$timezone"; return 1; }
  [[ "$timezone" != "$current" ]] || { info "时区未变化。"; return 0; }
  confirm "将时区修改为 $timezone？" || return 0; require_root; backup_file /etc/timezone
  run timedatectl set-timezone "$timezone"; audit "action=set-timezone value=$timezone"
}

system_create_swap() {
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
  ui_header "时间同步"; timedatectl status 2>/dev/null | sed -n '1,10p' || true
  confirm "启用 systemd 时间同步？" || return 0; require_root; run timedatectl set-ntp true; audit "action=enable-time-sync"
}

system_package_health() {
  ui_header "软件包状态"
  dpkg --audit 2>/dev/null || true
  printf '\n可更新软件：%s\n' "$(package_upgradable_count)"
  printf 'APT 缓存：%s\n' "$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || printf '未知')"
}

system_disk_usage() { ui_header "磁盘与目录"; df -hT; printf '\n主要目录：\n'; du -x -h --max-depth=1 /var /home 2>/dev/null | sort -h | tail -n 20 || true; }

system_processes() {
  ui_header "进程与资源"
  ui_section "内存占用最高"
  ps -eo pid,user,%cpu,%mem,rss,stat,comm --sort=-%mem 2>/dev/null | sed -n '1,16p'
  ui_section "CPU 占用最高"
  ps -eo pid,user,%cpu,%mem,etime,stat,comm --sort=-%cpu 2>/dev/null | sed -n '1,16p'
}

system_user_sessions() {
  ui_header "用户与登录会话"
  ui_section "当前会话"
  who 2>/dev/null || true
  ui_section "最近登录"
  last -n 20 2>/dev/null || ui_empty "没有可显示的登录记录"
  ui_section "可登录账户"
  awk -F: '$7 !~ /(nologin|false)$/ {printf "  %-18s uid=%s shell=%s\n",$1,$3,$7}' /etc/passwd
}

system_schedules() {
  ui_header "计划任务"
  ui_section "即将运行的 systemd Timer"
  systemctl list-timers --all --no-pager 2>/dev/null | sed -n '1,30p' || ui_empty "无法读取 Timer"
  ui_section "当前用户 Crontab"
  if command_exists crontab; then
    crontab -l 2>/dev/null || ui_empty "当前用户没有 Crontab"
  else
    ui_empty "未安装 cron"
  fi
  ui_section "系统 Cron 目录"
  find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly \
    -maxdepth 1 -type f -printf '  %p\n' 2>/dev/null | sort | sed -n '1,40p'
}

system_reboot_status() {
  ui_header "重启与内核状态"
  ui_kv "当前内核" "$(uname -r)"
  if [[ -f /var/run/reboot-required ]]; then
    doctor_result warn "系统提示需要重启"
    if [[ -r /var/run/reboot-required.pkgs ]]; then
      ui_section "触发重启提示的软件包"
      sed -n '1,30p' /var/run/reboot-required.pkgs
    fi
  else
    doctor_result pass "当前没有重启提示"
  fi
  ui_section "最近启动"
  journalctl --list-boots --no-pager 2>/dev/null | tail -n 8 || true
}

system_cleanup() {
  ui_header "安全清理"
  ui_kv "APT 缓存" "$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || printf '未知')"
  ui_kv "Journal" "$(journalctl --disk-usage 2>/dev/null | sed 's/.*take up //')"
  confirm "清理 APT 缓存并保留最近 14 天 Journal？" || return 0; require_root
  apt_run clean
  run journalctl --vacuum-time=14d
  audit "action=system-cleanup"
}

system_menu() {
  local choice
  while true; do
    ui_clear
    ui_header "系统管理"
    ui_section "状态与诊断"
    ui_item 1 "系统仪表盘" "资源与服务总览"
    ui_item 2 "环境检查" "运行依赖与连通性"
    ui_item 3 "进程与资源" "CPU、内存占用排行"
    ui_item 4 "用户与会话" "在线用户和最近登录"
    ui_item 5 "计划任务" "systemd Timer 与 Cron"
    ui_item 6 "重启状态" "内核、重启提示与启动历史"
    ui_item 7 "软件包状态" "dpkg 健康、更新与缓存"
    ui_item 8 "磁盘分析" "文件系统与主要目录"
    ui_section "系统设置"
    ui_item 9 "修改主机名"
    ui_item 10 "修改时区"
    ui_item 11 "创建 Swap"
    ui_item 12 "时间同步"
    ui_item 13 "安全清理" "APT 缓存和旧 Journal"
    ui_section "项目"
    ui_item 14 "关于本项目"
    ui_item 15 "卸载本项目" "程序卸载或彻底清除项目数据"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) dashboard_show ;;
      2) system_doctor ;;
      3) system_processes ;;
      4) system_user_sessions ;;
      5) system_schedules ;;
      6) system_reboot_status ;;
      7) system_package_health ;;
      8) system_disk_usage ;;
      9) system_set_hostname || true ;;
      10) system_set_timezone || true ;;
      11) system_create_swap || true ;;
      12) system_time_sync || true ;;
      13) system_cleanup || true ;;
      14) toolkit_about ;;
      15) toolkit_uninstall || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
