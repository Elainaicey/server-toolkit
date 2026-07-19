#!/usr/bin/env bash

monitor_install_tools() {
  log_step "安装监控与排障工具"
  catalog_install_bundle monitor || true
  systemctl list-unit-files | grep -q '^sysstat\.service' && run systemctl enable --now sysstat || true
}

tools_install_modern_cli() {
  log_step "安装现代命令行工具"
  catalog_install_bundle cli || true
}

tools_install_network_tools() {
  log_step "安装网络诊断工具"
  catalog_install_bundle network || true
}

tools_install_backup_tools() {
  log_step "安装备份/同步工具"
  catalog_install_bundle backup || true
}

tools_install_security_tools() {
  log_step "安装安全常用工具"
  catalog_install_bundle security || true
}

monitor_menu() {
  require_root
  detect_system
  clear_screen
  ui_panel_start "监控工具"
  ui_panel_line "[01] 按单项选择监控工具"
  ui_panel_line "[02] 安装完整监控排障集合"
  ui_panel_line "[00] 返回"
  ui_panel_end
  printf '\n'
  local choice
  choice="$(ask_input "请选择" "01")"
  case "$choice" in
    1|01) catalog_category_menu monitor ;;
    2|02) pkg_update_index; monitor_install_tools ;;
    0|00) return 0 ;;
  esac
  pause
}

tools_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    ui_panel_start "监控 / 排障 / 备份工具"
    ui_panel_line "[01] 监控排障工具    按单项选择"
    ui_panel_line "[02] 现代 CLI 工具   按单项选择"
    ui_panel_line "[03] 网络诊断工具    按单项选择"
    ui_panel_line "[04] 备份同步工具    按单项选择"
    ui_panel_line "[05] 安全常用工具    按单项选择"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) catalog_category_menu monitor ;;
      2|02) catalog_category_menu cli ;;
      3|03) catalog_category_menu network ;;
      4|04) catalog_category_menu backup ;;
      5|05) catalog_category_menu security ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}
