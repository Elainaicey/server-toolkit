#!/usr/bin/env bash

services_pick_from_output() {
  local units="$1" expected_state="$2" service
  [[ -n "$units" ]] || return 0
  service="$(read_input "输入完整服务名进入管理；输入 0 返回" "0")"
  [[ "$service" == "0" ]] && return 0
  valid_service_name "$service" || { warn "服务名格式无效。"; return 1; }
  awk '{print $1}' <<<"$units" | grep -Fxq "$service" || {
    warn "$service 不在当前 $expected_state 清单中。"
    return 1
  }
  services_select "$service"
}

services_running() {
  local units
  ui_page "运行中的服务" "查看 active 服务，并直接进入生命周期管理"
  units="$(systemctl --type=service --state=running --no-pager --no-legend --plain 2>/dev/null | sed -n '1,100p')"
  if [[ -n "$units" ]]; then printf '%s\n' "$units"; else ui_empty "没有运行中的服务"; fi
  services_pick_from_output "$units" "running" || true
}

services_failed() {
  local units
  ui_page "失败的服务" "检查 failed 单元，并直接查看日志或重启"
  units="$(systemctl --failed --type=service --no-pager --no-legend --plain 2>/dev/null | sed -n '1,100p')"
  if [[ -n "$units" ]]; then printf '%s\n' "$units"; else ui_check pass "没有 failed 服务"; fi
  services_pick_from_output "$units" "failed" || true
}

services_boot_errors() {
  ui_page "本次启动的错误日志" "当前 boot 的 error 级别 Journal"
  journalctl -b -p err --no-pager -n 120 2>/dev/null || ui_empty "无法读取 Journal"
}

services_timers() {
  local timer
  while true; do
    ui_page "systemd Timer" "查看计划、选择单元并控制调度生命周期"
    systemctl list-timers --all --no-pager 2>/dev/null || ui_empty "无法读取 Timer"
    timer="$(read_input "输入完整 Timer 名称进行管理；输入 0 返回" "0")"
    [[ "$timer" == "0" ]] && return 0
    if ! valid_service_name "$timer" || [[ "$timer" != *.timer ]]; then
      warn "Timer 名称格式无效。"
      pause
      continue
    fi
    unit_exists "$timer" || { warn "没有找到 Timer：$timer"; pause; continue; }
    services_timer_select "$timer"
  done
}

services_journal_kernel_warnings() {
  ui_page "内核警告" "本次启动最近 120 条 warning 及以上日志"
  journalctl -k -b -p warning --no-pager -n 120 2>/dev/null || ui_empty "没有可显示的内核警告"
}

services_journal_vacuum() {
  local mode="$1" value option description
  case "$mode" in
    time)
      value="$(read_input "保留最近多少天" "14")"
      if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 3650 )); then
        warn "天数必须在 1-3650 之间。"
        return 1
      fi
      option="--vacuum-time=${value}d"
      description="删除早于 $value 天的归档 Journal"
      ;;
    size)
      value="$(read_input "Journal 最大占用（MiB）" "500")"
      if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 32 || value > 10240 )); then
        warn "容量必须在 32-10240 MiB 之间。"
        return 1
      fi
      option="--vacuum-size=${value}M"
      description="把归档 Journal 压缩到 $value MiB 以内"
      ;;
    *) warn "未知 Journal 清理模式：$mode"; return 1 ;;
  esac
  ui_danger "$description；被清理的历史日志无法恢复。"
  confirm "确认执行 Journal 清理？" || return 0
  require_root
  run journalctl --rotate || { warn "无法轮转当前 Journal。"; return 1; }
  run journalctl "$option" || { warn "Journal 清理失败。"; return 1; }
  audit "action=journal-vacuum mode=$mode value=$value"
  ui_success "Journal 清理完成"
}

services_journal_info() {
  local action usage storage boots
  while true; do
    usage="$(journalctl --disk-usage 2>/dev/null | sed 's/^Archived and active journals take up //;s/\.$//' || printf '未知')"
    if [[ -d /var/log/journal ]]; then storage="持久化"; else storage="易失（随重启清理）"; fi
    boots="$(journalctl --list-boots --no-pager 2>/dev/null | grep -c . || true)"
    ui_page "Journal 管理" "磁盘占用、完整性验证、内核警告与历史清理"
    ui_panel_begin "日志存储"
    ui_panel_kv "磁盘占用" "${usage:-未知}"
    ui_panel_kv "存储模式" "$storage"
    ui_panel_kv "可查询启动" "$boots"
    ui_panel_end
    ui_section "查看与验证" "primary"
    ui_action_pair 1 "查看内核警告" "action" 2 "验证 Journal 文件" "action"
    ui_action 3 "查看磁盘占用详情" "action"
    ui_section "空间维护" "accent"
    ui_action_pair 4 "按时间清理" "warning" 5 "按容量清理" "warning"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) services_journal_kernel_warnings; pause ;;
      2)
        ui_page "验证 Journal" "读取所有 Journal 文件并检查一致性"
        if journalctl --verify 2>&1 | sed -n '1,160p'; then
          ui_success "Journal 文件验证通过"
        else
          warn "Journal 验证发现异常，请检查上方输出。"
        fi
        pause
        ;;
      3) journalctl --disk-usage 2>/dev/null || true; pause ;;
      4) services_journal_vacuum time || true; pause ;;
      5) services_journal_vacuum size || true; pause ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

services_timer_select() {
  local timer="$1" action state enabled description next last trigger accuracy
  unit_exists "$timer" || { warn "没有找到 Timer：$timer"; return 1; }
  while true; do
    state="$(service_state "$timer")"
    enabled="$(systemctl is-enabled "$timer" 2>/dev/null || true)"
    enabled="${enabled:-disabled}"
    description="$(systemctl show "$timer" -p Description --value 2>/dev/null || true)"
    next="$(systemctl show "$timer" -p NextElapseUSecRealtime --value 2>/dev/null || true)"
    last="$(systemctl show "$timer" -p LastTriggerUSec --value 2>/dev/null || true)"
    trigger="$(systemctl show "$timer" -p Triggers --value 2>/dev/null | awk 'NF{print $1;exit}' || true)"
    accuracy="$(systemctl show "$timer" -p AccuracyUSec --value 2>/dev/null || true)"
    ui_page "Timer 管理 / $timer" "计划信息、日志、生命周期与关联任务"
    ui_panel_begin "Timer 信息"
    ui_panel_kv "说明" "${description:-—}"
    if [[ "$state" == "active" ]]; then ui_panel_kv "状态" "● $state" "$GREEN"; else ui_panel_kv "状态" "● $state" "$YELLOW"; fi
    ui_panel_kv "开机启用" "$enabled"
    ui_panel_kv "下次运行" "${next:-—}"
    ui_panel_kv "上次运行" "${last:-—}"
    ui_panel_kv "关联单元" "${trigger:-—}"
    ui_panel_kv "触发精度" "${accuracy:-—}"
    ui_panel_end
    ui_section "查看" "primary"
    ui_action_pair 1 "查看 Timer 状态" "action" 2 "查看 Timer 日志" "action"
    ui_action 3 "查看关联任务日志" "action" "${trigger:-未检测到关联单元}"
    ui_section "调度控制" "accent"
    if [[ "$state" == "active" ]]; then
      ui_action_pair 4 "启动 Timer（已运行）" "muted" 5 "停止 Timer" "danger"
    else
      ui_action_pair 4 "启动 Timer" "success" 5 "停止 Timer（未运行）" "muted"
    fi
    ui_action_pair 6 "重启 Timer" "warning" 9 "立即运行关联任务" "warning"
    if [[ "$enabled" == "enabled" ]]; then
      ui_action_pair 7 "开机调度（已启用）" "muted" 8 "禁用开机调度" "danger"
    else
      ui_action_pair 7 "启用开机调度" "success" 8 "开机调度（未启用）" "muted"
    fi
    [[ -n "$trigger" ]] || ui_note "当前 Timer 没有可识别的关联任务，选项 9 不可用。"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) systemctl status "$timer" --no-pager || true; pause ;;
      2) journalctl -u "$timer" -n 100 --no-pager 2>/dev/null || true; pause ;;
      3)
        if [[ -n "$trigger" ]]; then services_logs "$trigger"; else warn "没有检测到关联任务。"; fi
        pause
        ;;
      4) services_apply_unit_action "$timer" start || true; pause ;;
      5) services_apply_unit_action "$timer" stop || true; pause ;;
      6) services_apply_unit_action "$timer" restart || true; pause ;;
      7) services_apply_unit_action "$timer" enable || true; pause ;;
      8) services_apply_unit_action "$timer" disable || true; pause ;;
      9)
        if [[ -n "$trigger" ]]; then services_apply_unit_action "$trigger" start || true; else warn "没有检测到关联任务。"; fi
        pause
        ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

services_logs() {
  local service="$1"
  ui_page "$service 日志" "最近 100 条 Journal"
  journalctl -u "$service" -n 100 --no-pager 2>/dev/null || warn "无法读取日志。"
}

services_search() {
  local query service
  query="$(read_input "服务关键词" "")"; [[ -n "$query" ]] || return 0
  [[ "$query" =~ ^[a-zA-Z0-9@_.:-]+$ ]] || { warn "关键词格式无效。"; return 1; }
  ui_page "查找 systemd 服务" "$query · 匹配单元名或描述"
  systemctl list-units --all --type=service --no-legend --no-pager 2>/dev/null |
    awk -v query="$query" 'BEGIN{query=tolower(query)} index(tolower($0),query){print "  "$0; found=1} END{if(!found)print "  — 没有匹配的服务"}' |
    sed -n '1,80p'
  service="$(read_input "输入完整服务名进行管理；输入 0 返回" "0")"
  [[ "$service" == "0" ]] && return 0
  valid_service_name "$service" || { warn "服务名格式无效。"; return 1; }
  services_select "$service"
}

services_apply_unit_action() {
  local unit="$1" verb="$2" label unit_type result
  valid_service_name "$unit" || { warn "systemd 单元名格式无效。"; return 1; }
  unit_exists "$unit" || { warn "没有找到 systemd 单元：$unit"; return 1; }
  case "$verb" in
    start) label="启动" ;;
    stop) label="停止" ;;
    restart) label="重启" ;;
    enable) label="启用开机启动" ;;
    disable) label="禁用开机启动" ;;
    *) warn "不支持的 systemd 操作：$verb"; return 1 ;;
  esac
  confirm "对 $unit 执行「$label」？" || return 0
  require_root
  run systemctl "$verb" "$unit" || { warn "$unit：$label命令执行失败。"; return 1; }
  if [[ "$DRY_RUN" -eq 0 ]]; then
    case "$verb" in
      start|restart)
        unit_type="$(systemctl show "$unit" -p Type --value 2>/dev/null || true)"
        if [[ "$unit_type" == "oneshot" ]]; then
          result="$(systemctl show "$unit" -p Result --value 2>/dev/null || true)"
          [[ "$result" == "success" ]] || { warn "$unit 执行结果不是 success。"; return 1; }
        else
          systemctl is-active --quiet "$unit" || { warn "$unit 操作后仍未运行。"; return 1; }
        fi
        ;;
      stop)
        if systemctl is-active --quiet "$unit"; then warn "$unit 操作后仍在运行。"; return 1; fi
        ;;
      enable)
        systemctl is-enabled --quiet "$unit" || { warn "$unit 尚未启用开机启动。"; return 1; }
        ;;
      disable)
        if systemctl is-enabled --quiet "$unit"; then warn "$unit 仍处于开机启动状态。"; return 1; fi
        ;;
    esac
  fi
  audit "action=systemd-$verb unit=$unit"
  ui_success "$unit：$label已完成"
}

services_apply_action() {
  local service="$1" verb="$2"
  service_exists "$service" || { warn "没有找到服务：$service"; return 1; }
  services_apply_unit_action "$service" "$verb"
}

services_select() {
  local service="${1:-}" action state enabled description substate main_pid restarts started
  [[ -n "$service" ]] || service="$(read_input "服务名（例如 nginx.service）" "")"
  [[ -n "$service" ]] || return 0
  valid_service_name "$service" || { warn "服务名格式无效。"; return 1; }
  service_exists "$service" || { warn "没有找到服务：$service"; return 1; }
  while true; do
    state="$(service_state "$service")"
    enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
    enabled="${enabled:-disabled}"
    description="$(systemctl show "$service" -p Description --value 2>/dev/null || true)"
    substate="$(systemctl show "$service" -p SubState --value 2>/dev/null || true)"
    main_pid="$(systemctl show "$service" -p MainPID --value 2>/dev/null || true)"
    restarts="$(systemctl show "$service" -p NRestarts --value 2>/dev/null || true)"
    started="$(systemctl show "$service" -p ActiveEnterTimestamp --value 2>/dev/null || true)"
    ui_page "服务管理 / $service" "状态、日志、生命周期与开机启动"
    ui_panel_begin "服务信息"
    ui_panel_kv "说明" "${description:-—}"
    if [[ "$state" == "active" ]]; then ui_panel_kv "状态" "● $state" "$GREEN"; else ui_panel_kv "状态" "● $state" "$YELLOW"; fi
    ui_panel_kv "子状态" "${substate:-—}"
    ui_panel_kv "开机启动" "$enabled"
    ui_panel_kv "主进程 PID" "${main_pid:-0}"
    ui_panel_kv "重启次数" "${restarts:-0}"
    ui_panel_kv "进入状态时间" "${started:-—}"
    ui_panel_end
    ui_section "查看" "primary"
    ui_action 1 "查看状态" "action"
    ui_action 2 "查看日志" "action"
    ui_action 3 "查看依赖关系" "action"
    ui_section "生命周期" "accent"
    if [[ "$state" == "active" ]]; then
      ui_action 4 "启动" "muted" "服务已经运行"
      ui_action 5 "停止" "danger"
      ui_action 6 "重启" "warning"
    else
      ui_action 4 "启动" "success"
      ui_action 5 "停止" "muted" "服务当前未运行"
      ui_action 6 "重启" "warning"
    fi
    if [[ "$enabled" == "enabled" ]]; then
      ui_action 7 "启用开机启动" "muted" "当前已经启用"
      ui_action 8 "禁用开机启动" "danger"
    else
      ui_action 7 "启用开机启动" "success"
      ui_action 8 "禁用开机启动" "muted" "当前未启用"
    fi
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) systemctl status "$service" --no-pager || true; pause ;;
      2) services_logs "$service"; pause ;;
      3) systemctl list-dependencies "$service" --no-pager 2>/dev/null || true; pause ;;
      4|5|6|7|8)
        local verb=""
        case "$action" in
          4) verb=start ;;
          5) verb=stop ;;
          6) verb=restart ;;
          7) verb=enable ;;
          8) verb=disable ;;
        esac
        services_apply_action "$service" "$verb" || true
        pause
        ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

services_audit_log() {
  ui_page "项目操作记录" "最近 100 条系统修改审计"
  if [[ -r "$AUDIT_LOG" ]]; then
    tail -n 100 "$AUDIT_LOG"
  else
    ui_empty "尚无操作记录"
  fi
}

services_menu() {
  local choice
  while true; do
    ui_page "服务与日志" "systemd 单元、Timer、Journal 与项目操作审计"
    ui_section "服务状态" "primary"
    ui_item 1 "失败的服务" "优先处理异常单元"
    ui_item 2 "运行中的服务"
    ui_item 3 "查找服务" "按名称筛选并进入管理"
    ui_item 4 "管理一个服务" "状态、详情、日志、依赖与生命周期"
    ui_section "日志与计划" "accent"
    ui_item 5 "启动错误" "本次开机的 error 级别 Journal"
    ui_item 6 "systemd Timer 管理" "计划、日志、启停与立即运行关联任务"
    ui_item 7 "Journal 管理" "验证、内核警告与按时间/容量清理"
    ui_item 8 "项目操作记录"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) services_failed ;;
      2) services_running ;;
      3) services_search || true ;;
      4) services_select || true ;;
      5) services_boot_errors ;;
      6) services_timers; continue ;;
      7) services_journal_info; continue ;;
      8) services_audit_log ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
