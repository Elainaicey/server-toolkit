#!/usr/bin/env bash

services_running() { ui_header "运行中的服务"; systemctl --type=service --state=running --no-pager --no-legend 2>/dev/null | sed -n '1,100p'; }
services_failed() { ui_header "失败的服务"; systemctl --failed --no-pager 2>/dev/null || true; }

services_boot_errors() {
  ui_header "本次启动的错误日志"
  journalctl -b -p err --no-pager -n 120 2>/dev/null || ui_empty "无法读取 Journal"
}

services_timers() {
  ui_header "systemd Timer"
  systemctl list-timers --all --no-pager 2>/dev/null || ui_empty "无法读取 Timer"
}

services_journal_info() {
  ui_header "Journal 状态"
  journalctl --disk-usage 2>/dev/null || true
  ui_section "最近的内核警告"
  journalctl -k -b -p warning --no-pager -n 80 2>/dev/null || ui_empty "没有可显示的内核警告"
}

services_logs() {
  local service="$1"
  ui_header "$service 日志"
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
    ui_clear
    ui_header "$service"
    ui_kv "状态" "$state"
    ui_kv "开机启动" "$enabled"
    ui_item 1 "查看状态"
    ui_item 2 "查看日志"
    ui_item 3 "启动"
    ui_item 4 "停止"
    ui_item 5 "重启"
    ui_item 6 "启用开机启动"
    ui_item 7 "禁用开机启动"
    ui_item 0 "返回"
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
  ui_header "Server Toolkit 操作记录"
  if [[ -r "$AUDIT_LOG" ]]; then
    tail -n 100 "$AUDIT_LOG"
  else
    ui_empty "尚无操作记录"
  fi
}

services_menu() {
  local choice
  while true; do
    ui_clear
    ui_header "服务与日志"
    ui_item 1 "失败的服务" "优先处理异常单元"
    ui_item 2 "运行中的服务"
    ui_item 3 "管理一个服务" "状态、日志、启动、停止与开机启动"
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
