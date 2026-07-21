#!/usr/bin/env bash

system_overview() { dashboard_show; }

HEALTH_PASS=0
HEALTH_WARN=0
HEALTH_FAIL=0

health_result() {
  local state="$1" message="$2" hint="${3:-}"
  case "$state" in
    pass) HEALTH_PASS=$((HEALTH_PASS + 1)) ;;
    warn) HEALTH_WARN=$((HEALTH_WARN + 1)) ;;
    fail) HEALTH_FAIL=$((HEALTH_FAIL + 1)) ;;
    *) die "未知巡检状态：$state" ;;
  esac
  ui_check "$state" "$message"
  [[ -z "$hint" ]] || printf '    %b↳ %s%b\n' "$MUTED" "$hint" "$NC"
}

system_health_report() {
  platform_detect
  HEALTH_PASS=0; HEALTH_WARN=0; HEALTH_FAIL=0
  local package_audit free_mb inode_percent memory_percent load_one failed_units oom_count upgrades ssh_settings
  package_audit="$(dpkg --audit 2>/dev/null || true)"
  free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"
  inode_percent="$(df -Pi / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')"
  memory_percent=0
  if [[ "$MEMORY_USED_MB" =~ ^[0-9]+$ && "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB > 0 )); then
    memory_percent=$((MEMORY_USED_MB * 100 / MEMORY_MB))
  fi
  load_one="${LOAD_AVERAGE%% *}"
  failed_units="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
  oom_count="$(journalctl -k -b --no-pager 2>/dev/null | grep -Eic 'out of memory|oom-killer|killed process' || true)"
  upgrades="$(package_upgradable_count)"

  ui_page "系统健康巡检" "资源、服务、软件包、网络、时间与安全基线的只读汇总"
  ui_section "平台与资源" "primary"
  health_result pass "$OS_NAME · $ARCH · $VIRTUALIZATION"
  if [[ -z "$package_audit" ]]; then
    health_result pass "dpkg 软件包状态正常"
  else
    health_result fail "存在未完成的软件包配置" "进入【软件包与更新】查看 dpkg 审计结果"
  fi
  if [[ "$ROOT_USED_PERCENT" =~ ^[0-9]+$ ]] && (( ROOT_USED_PERCENT >= 95 )); then
    health_result fail "根分区使用率 ${ROOT_USED_PERCENT}%" "尽快检查日志、缓存和业务数据"
  elif [[ "$ROOT_USED_PERCENT" =~ ^[0-9]+$ ]] && (( ROOT_USED_PERCENT >= 85 )); then
    health_result warn "根分区使用率 ${ROOT_USED_PERCENT}% · 可用 ${free_mb:-未知} MiB" "进入【存储诊断】定位空间占用"
  else
    health_result pass "根分区空间正常 · 使用 ${ROOT_USED_PERCENT:-未知}% · 可用 ${free_mb:-未知} MiB"
  fi
  if [[ "$inode_percent" =~ ^[0-9]+$ ]] && (( inode_percent >= 90 )); then
    health_result warn "根分区 inode 使用率 ${inode_percent}%" "大量小文件可能耗尽 inode"
  else
    health_result pass "根分区 inode 余量正常 · 使用 ${inode_percent:-未知}%"
  fi
  if (( memory_percent >= 90 )); then
    health_result fail "内存使用率 ${memory_percent}%" "检查高内存进程与 OOM 日志"
  elif (( memory_percent >= 75 )); then
    health_result warn "内存使用率 ${memory_percent}%" "关注持续增长的进程"
  else
    health_result pass "内存使用率 ${memory_percent}%"
  fi
  if awk -v current_load="$load_one" -v cpu_count="$CPU_CORES" 'BEGIN{exit !(cpu_count > 0 && current_load > cpu_count)}'; then
    health_result warn "1 分钟负载 $load_one，高于 $CPU_CORES 个 CPU 核心" "进入【进程与资源】定位占用"
  else
    health_result pass "1 分钟负载 $load_one / $CPU_CORES vCPU"
  fi
  if (( oom_count > 0 )); then
    health_result warn "本次启动检测到 $oom_count 条 OOM 相关日志" "检查内存压力与被终止的进程"
  else
    health_result pass "本次启动未检测到 OOM"
  fi

  ui_section "服务与维护" "accent"
  if (( failed_units > 0 )); then
    health_result fail "$failed_units 个 systemd 单元处于失败状态" "进入【服务与日志】查看失败单元"
  else
    health_result pass "systemd 没有失败单元"
  fi
  if [[ "$upgrades" =~ ^[0-9]+$ ]] && (( upgrades > 0 )); then
    health_result warn "$upgrades 个系统软件包可更新" "进入【软件包与更新】查看版本清单"
  else
    health_result pass "本地索引中没有可更新软件包"
  fi
  if [[ -f /var/run/reboot-required ]]; then
    health_result warn "系统提示需要重启" "先检查业务状态并安排维护窗口"
  else
    health_result pass "没有待处理的重启提示"
  fi
  if command_exists timedatectl && [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]; then
    health_result pass "系统时间已同步"
  else
    health_result warn "未确认系统时间同步状态" "检查 NTP 服务与上游时间源"
  fi

  ui_section "网络与安全" "primary"
  if getent hosts github.com >/dev/null 2>&1; then
    health_result pass "DNS 解析正常"
  else
    health_result fail "DNS 解析失败" "检查 /etc/resolv.conf 和网络路由"
  fi
  if command_exists curl && curl -fsI --connect-timeout 3 --max-time 8 https://github.com >/dev/null 2>&1; then
    health_result pass "HTTPS 出站连接正常"
  else
    health_result warn "未能验证 HTTPS 出站连接" "检查时间、DNS、路由和 CA 证书"
  fi
  if platform_firewall_active; then
    health_result pass "UFW 主机防火墙已启用"
  else
    health_result warn "UFW 主机防火墙未启用" "还需结合服务商云防火墙判断实际暴露面"
  fi
  if command_exists sshd; then
    ssh_settings="$(sshd -T 2>/dev/null || true)"
    if grep -q '^passwordauthentication no$' <<<"$ssh_settings"; then
      health_result pass "SSH 密码登录已禁用"
    else
      health_result warn "SSH 仍允许密码登录" "确认公钥可用后再通过 SSH 安全向导调整"
    fi
  else
    health_result warn "无法读取 sshd 有效配置"
  fi

  ui_section "巡检结论" "accent"
  ui_health_summary "$HEALTH_PASS" "$HEALTH_WARN" "$HEALTH_FAIL"
  if (( HEALTH_FAIL > 0 )); then
    ui_danger "检测到 $HEALTH_FAIL 项异常；建议优先处理红色项目。"
  elif (( HEALTH_WARN > 0 )); then
    ui_note "系统可以运行，但有 $HEALTH_WARN 项值得关注。"
  else
    ui_success "当前检查项全部正常。"
  fi
  ui_note "巡检为当前时刻的只读快照，不会自动修改系统。"
}

system_doctor() {
  platform_detect
  ui_page "环境检查" "系统支持、软件包状态、存储、网络与运行时依赖"
  ui_check pass "$OS_NAME ($ARCH)"
  if command_exists apt-get; then ui_check pass "APT 可用"; else ui_check fail "缺少 apt-get"; fi
  local audit; audit="$(dpkg --audit 2>/dev/null || true)"
  if [[ -z "$audit" ]]; then ui_check pass "软件包状态正常"; else ui_check fail "存在未完成的软件包配置"; fi
  local free_mb; free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"
  if [[ "$free_mb" =~ ^[0-9]+$ ]] && (( free_mb >= 512 )); then ui_check pass "根分区可用 ${free_mb} MB"; else ui_check warn "根分区剩余不足 512 MB"; fi
  if getent hosts deb.debian.org >/dev/null 2>&1; then ui_check pass "DNS 解析正常"; else ui_check fail "DNS 解析失败"; fi
  if command_exists curl && curl -fsI --connect-timeout 2 --max-time 5 https://github.com >/dev/null 2>&1; then ui_check pass "HTTPS 与 GitHub 可用"; else ui_check warn "未能访问 GitHub"; fi
  if [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB < 512 )) && [[ "$SWAP_MB" == "0" ]]; then ui_check warn "低内存且没有 Swap"; else ui_check pass "内存与 Swap 状态可用"; fi
  if command_exists systemctl; then
    ui_check pass "systemd 可用"
  else
    ui_check fail "systemd 不可用"
  fi
}

system_package_health() {
  local audit updates held cache_size
  audit="$(dpkg --audit 2>/dev/null || true)"
  updates="$(package_upgradable_count)"
  held="$(apt-mark showhold 2>/dev/null || true)"
  cache_size="$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || printf '未知')"
  ui_page "软件包与更新" "dpkg 健康、候选版本、保留包与 APT 缓存"
  ui_panel_begin "状态摘要"
  ui_panel_kv "可更新" "$updates 个" "$YELLOW"
  ui_panel_kv "保留包" "$(grep -c . <<<"$held" || true) 个"
  ui_panel_kv "APT 缓存" "$cache_size"
  ui_panel_end
  ui_section "dpkg 审计" "primary"
  if [[ -n "$audit" ]]; then printf '%s\n' "$audit"; else ui_success "没有未完成的软件包配置。"; fi
  ui_section "可用更新" "accent"
  if [[ "$updates" =~ ^[0-9]+$ ]] && (( updates > 0 )); then
    apt list --upgradable 2>/dev/null | sed -n '2,82p'
    (( updates > 80 )) && ui_note "仅显示前 80 项，共 $updates 项。"
  else
    ui_empty "本地 APT 索引中没有可用更新"
  fi
  ui_section "被保留的软件包" "primary"
  if [[ -n "$held" ]]; then printf '%s\n' "$held"; else ui_empty "没有被 apt-mark hold 的软件包"; fi
  ui_note "这是只读清单；单项软件更新仍从软件管理中心执行。"
}

system_disk_usage() {
  ui_page "存储诊断" "块设备、文件系统、inode、只读挂载与已删除占用"
  ui_section "块设备" "primary"
  if command_exists lsblk; then lsblk -o NAME,TYPE,FSTYPE,SIZE,FSAVAIL,FSUSE%,MOUNTPOINTS 2>/dev/null; else ui_empty "缺少 lsblk"; fi
  ui_section "文件系统空间" "accent"
  df -hT -x tmpfs -x devtmpfs 2>/dev/null || true
  ui_section "inode 使用" "primary"
  df -hi -x tmpfs -x devtmpfs 2>/dev/null || true
  ui_section "主要目录" "accent"
  du -x -h --max-depth=1 /var /home /opt /srv 2>/dev/null | sort -h | tail -n 24 || ui_empty "无法读取目录占用"
  ui_section "只读挂载" "primary"
  if command_exists findmnt; then
    local readonly_mounts
    readonly_mounts="$(findmnt -rn -o TARGET,OPTIONS 2>/dev/null | awk '$2 ~ /(^|,)ro(,|$)/ {print}')"
    if [[ -n "$readonly_mounts" ]]; then printf '%s\n' "$readonly_mounts"; else ui_empty "没有检测到只读文件系统"; fi
  else
    ui_empty "缺少 findmnt"
  fi
  ui_section "已删除但仍被进程占用的文件" "accent"
  if command_exists lsof; then
    local deleted
    deleted="$(lsof -nP +L1 2>/dev/null | sed -n '1,21p' || true)"
    if [[ -n "$deleted" ]]; then printf '%s\n' "$deleted"; else ui_empty "没有检测到已删除但仍占用空间的文件"; fi
  else
    ui_empty "未安装 lsof，跳过该检查"
  fi
}

system_processes() {
  ui_page "进程与资源" "按 CPU 和内存使用率查看高占用进程"
  ui_section "内存占用最高"
  ps -eo pid,user,%cpu,%mem,rss,stat,comm --sort=-%mem 2>/dev/null | sed -n '1,16p'
  ui_section "CPU 占用最高"
  ps -eo pid,user,%cpu,%mem,etime,stat,comm --sort=-%cpu 2>/dev/null | sed -n '1,16p'
}

system_pressure() {
  platform_detect
  ui_page "资源压力分析" "负载、内存、存储空间、inode 与 OOM 事件"
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

  ui_section "判断"
  if awk -v current_load="$load_one" -v cpu_count="$CPU_CORES" 'BEGIN{exit !(current_load > cpu_count)}'; then ui_check warn "负载已高于 CPU 核心数"; else ui_check pass "当前负载处于可控范围"; fi
  if (( memory_percent >= 90 )); then ui_check fail "内存使用率达到 ${memory_percent}%"; elif (( memory_percent >= 75 )); then ui_check warn "内存使用率达到 ${memory_percent}%"; else ui_check pass "内存余量正常"; fi
  if [[ "$root_percent" =~ ^[0-9]+$ ]] && (( root_percent >= 90 )); then ui_check fail "根分区空间紧张"; else ui_check pass "根分区空间正常"; fi
  if [[ "$inode_percent" =~ ^[0-9]+$ ]] && (( inode_percent >= 90 )); then ui_check warn "inode 使用率较高"; else ui_check pass "inode 余量正常"; fi
  if (( oom_count > 0 )); then ui_check warn "本次启动检测到 $oom_count 条 OOM 相关日志"; else ui_check pass "本次启动未检测到 OOM"; fi
}

system_user_sessions() {
  ui_page "用户与登录会话" "当前连接、最近登录与可交互账户"
  ui_section "当前会话"
  who 2>/dev/null || true
  ui_section "最近登录"
  last -n 20 2>/dev/null || ui_empty "没有可显示的登录记录"
  ui_section "可登录账户"
  awk -F: '$7 !~ /(nologin|false)$/ {printf "  %-18s uid=%s shell=%s\n",$1,$3,$7}' /etc/passwd
}

system_schedules() {
  ui_page "计划任务" "systemd Timer、用户 Crontab 和系统 Cron 目录"
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
  ui_page "重启与内核状态" "内核版本、重启提示与最近启动记录"
  ui_kv "当前内核" "$(uname -r)"
  if [[ -f /var/run/reboot-required ]]; then
    ui_check warn "系统提示需要重启"
    if [[ -r /var/run/reboot-required.pkgs ]]; then
      ui_section "触发重启提示的软件包"
      sed -n '1,30p' /var/run/reboot-required.pkgs
    fi
  else
    ui_check pass "当前没有重启提示"
  fi
  ui_section "最近启动"
  journalctl --list-boots --no-pager 2>/dev/null | tail -n 8 || true
}

system_menu() {
  local choice
  while true; do
    ui_page "系统管理" "状态诊断、基础配置与项目维护"
    ui_section "状态与诊断"
    ui_item 1 "系统仪表盘" "资源与服务总览"
    ui_item 2 "系统健康巡检" "资源、服务、更新、网络与安全汇总"
    ui_item 3 "环境检查" "运行依赖与连通性"
    ui_item 4 "资源压力分析" "负载、内存、空间、inode 与 OOM"
    ui_item 5 "进程与资源" "CPU、内存占用排行"
    ui_item 6 "用户与会话" "在线用户和最近登录"
    ui_item 7 "计划任务" "systemd Timer 与 Cron"
    ui_item 8 "重启状态" "内核、重启提示与启动历史"
    ui_item 9 "软件包与更新" "版本清单、保留包、dpkg 与缓存"
    ui_item 10 "存储诊断" "块设备、空间、inode 与占用排查"
    ui_section "系统设置"
    ui_item 11 "修改主机名"
    ui_item 12 "修改时区"
    ui_item 13 "创建 Swap"
    ui_item 14 "时间同步"
    ui_item 15 "安全清理" "APT 缓存和旧 Journal"
    ui_section "项目"
    ui_item 16 "关于本项目"
    ui_item 17 "检查项目更新" "比较本机与 GitHub 发布版本"
    ui_item 18 "更新本项目" "使用原子替换安装流程"
    ui_item 19 "卸载本项目" "程序卸载或彻底清除项目数据"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) dashboard_show ;;
      2) system_health_report ;;
      3) system_doctor ;;
      4) system_pressure ;;
      5) system_processes ;;
      6) system_user_sessions ;;
      7) system_schedules ;;
      8) system_reboot_status ;;
      9) system_package_health ;;
      10) system_disk_usage ;;
      11) system_set_hostname || true ;;
      12) system_set_timezone || true ;;
      13) system_create_swap || true ;;
      14) system_time_sync || true ;;
      15) system_cleanup || true ;;
      16) toolkit_about ;;
      17) toolkit_check_update || true ;;
      18) toolkit_self_update || true ;;
      19) toolkit_uninstall || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
