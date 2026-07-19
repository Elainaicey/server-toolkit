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

services_select() {
  local service action state enabled
  service="$(read_input "服务名（例如 nginx.service）" "")"
  [[ -n "$service" ]] || return 0
  valid_service_name "$service" || { warn "服务名格式无效。"; return 1; }
  service_exists "$service" || { warn "没有找到服务：$service"; return 1; }
  while true; do
    state="$(service_state "$service")"
    enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
    enabled="${enabled:-disabled}"
    ui_page "服务管理 / $service" "状态、日志、生命周期与开机启动"
    ui_panel_begin "服务信息"
    if [[ "$state" == "active" ]]; then ui_panel_kv "状态" "● $state" "$GREEN"; else ui_panel_kv "状态" "● $state" "$YELLOW"; fi
    ui_panel_kv "开机启动" "$enabled"
    ui_panel_end
    ui_section "查看" "primary"
    ui_action 1 "查看状态" "action"
    ui_action 2 "查看日志" "action"
    ui_section "生命周期" "accent"
    ui_action 3 "启动" "success"
    ui_action 4 "停止" "danger"
    ui_action 5 "重启" "warning"
    ui_action 6 "启用开机启动" "success"
    ui_action 7 "禁用开机启动" "danger"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) systemctl status "$service" --no-pager || true; pause ;;
      2) services_logs "$service"; pause ;;
      3|4|5|6|7)
        local verb
        case "$action" in
          3) verb=start ;;
          4) verb=stop ;;
          5) verb=restart ;;
          6) verb=enable ;;
          7) verb=disable ;;
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
    ui_item 3 "管理一个服务" "状态、日志、启动、停止与开机启动"
    ui_section "日志与计划" "accent"
    ui_item 4 "启动错误" "本次开机的 error 级别 Journal"
    ui_item 5 "systemd Timer"
    ui_item 6 "Journal 与内核警告"
    ui_item 7 "项目操作记录"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) services_failed ;;
      2) services_running ;;
      3) services_select || true ;;
      4) services_boot_errors ;;
      5) services_timers ;;
      6) services_journal_info ;;
      7) services_audit_log ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
