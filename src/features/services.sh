#!/usr/bin/env bash

services_running() { ui_page "运行中的服务" "最多显示前 100 个 active systemd 服务"; systemctl --type=service --state=running --no-pager --no-legend 2>/dev/null | sed -n '1,100p'; }
services_failed() { ui_page "失败的服务" "需要优先检查的 failed systemd 单元"; systemctl --failed --no-pager 2>/dev/null || true; }

services_boot_errors() {
  ui_page "本次启动的错误日志" "当前 boot 的 error 级别 Journal"
  journalctl -b -p err --no-pager -n 120 2>/dev/null || ui_empty "无法读取 Journal"
}

services_timers() {
  ui_page "systemd Timer" "所有计划运行的 Timer 单元"
  systemctl list-timers --all --no-pager 2>/dev/null || ui_empty "无法读取 Timer"
}

services_journal_info() {
  ui_page "Journal 状态" "磁盘占用和本次启动的内核警告"
  journalctl --disk-usage 2>/dev/null || true
  ui_section "最近的内核警告"
  journalctl -k -b -p warning --no-pager -n 80 2>/dev/null || ui_empty "没有可显示的内核警告"
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
    ui_action 4 "启动" "success"
    ui_action 5 "停止" "danger"
    ui_action 6 "重启" "warning"
    ui_action 7 "启用开机启动" "success"
    ui_action 8 "禁用开机启动" "danger"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) systemctl status "$service" --no-pager || true; pause ;;
      2) services_logs "$service"; pause ;;
      3) systemctl list-dependencies "$service" --no-pager 2>/dev/null || true; pause ;;
      4|5|6|7|8)
        local verb
        case "$action" in
          4) verb=start ;;
          5) verb=stop ;;
          6) verb=restart ;;
          7) verb=enable ;;
          8) verb=disable ;;
        esac
        confirm "对 $service 执行 $verb？" || continue
        require_root
        run systemctl "$verb" "$service"
        audit "action=service-$verb service=$service"
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
    ui_item 6 "systemd Timer"
    ui_item 7 "Journal 与内核警告"
    ui_item 8 "项目操作记录"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) services_failed ;;
      2) services_running ;;
      3) services_search || true ;;
      4) services_select || true ;;
      5) services_boot_errors ;;
      6) services_timers ;;
      7) services_journal_info ;;
      8) services_audit_log ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
