#!/usr/bin/env bash

repair_show_status() {
  print_title "系统修复状态"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    echo "dpkg --audit："
    dpkg --audit 2>/dev/null || true
    echo
    echo "被 hold 的软件包："
    apt-mark showhold 2>/dev/null || true
    echo
    echo "依赖/损坏检查："
    apt-get check 2>/dev/null || true
  else
    "$PM" check 2>/dev/null || true
  fi
}

repair_dpkg_configure() {
  [[ "$OS_FAMILY" == "debian" ]] || { log_warn "dpkg 修复仅适用于 Debian/Ubuntu。"; return 0; }
  ask_yes_no "是否执行 dpkg --configure -a？" "N" || return 0
  export DEBIAN_FRONTEND=noninteractive
  run dpkg --configure -a
}

repair_fix_broken() {
  [[ "$OS_FAMILY" == "debian" ]] || { log_warn "apt 修复仅适用于 Debian/Ubuntu。"; return 0; }
  ask_yes_no "是否执行 apt-get --fix-broken install？" "N" || return 0
  apt_get -f install -y
}

repair_hold_grub() {
  [[ "$OS_FAMILY" == "debian" ]] || { log_warn "apt-mark hold 仅适用于 Debian/Ubuntu。"; return 0; }
  log_warn "这适合 grub-pc 因磁盘 ID 不存在而配置失败的 VPS。"
  ask_yes_no "是否 hold grub-pc 和 grub-common？" "N" || return 0
  run apt-mark hold grub-pc grub-common || true
}

repair_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    repair_show_status
    printf '\n'
    ui_panel_start "修复操作"
    ui_panel_line "[01] 执行 dpkg --configure -a"
    ui_panel_line "[02] 执行 apt --fix-broken install"
    ui_panel_line "[03] hold grub 相关软件包"
    ui_panel_line "[04] 生成系统报告"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) repair_dpkg_configure ;;
      2|02) repair_fix_broken ;;
      3|03) repair_hold_grub ;;
      4|04) generate_report ;;
      0|00) break ;;
    esac
    pause
  done
}

maintenance_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    ui_panel_start "系统修复与回滚"
    ui_panel_line "[01] 查看/修复 APT 或 dpkg 状态"
    ui_panel_line "[02] 回滚备份文件"
    ui_panel_line "[03] 生成系统报告"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) repair_menu ;;
      2|02) rollback_menu ;;
      3|03) generate_report; pause ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
  done
}
