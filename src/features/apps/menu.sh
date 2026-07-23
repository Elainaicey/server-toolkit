#!/usr/bin/env bash

apps_menu() {
  local choice
  while true; do
    ui_page "应用与容器" "集中管理应用资产、运行健康、服务生命周期与容器"
    ui_context "所有检查均按需执行；不会创建监控进程、Cron 或 Timer，也不会隐式修改防火墙。"
    ui_section "应用服务" "primary"
    ui_item 1 "应用服务管理" "版本、健康、端口、配置、数据、日志与安全 reload"
    ui_section "容器" "accent"
    ui_item 2 "Docker" "容器、镜像、网络、存储卷与清理"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) apps_service_manage ;;
      2) docker_menu ;;
      0) return 0 ;;
      *) warn "未知选项"; pause ;;
    esac
  done
}
