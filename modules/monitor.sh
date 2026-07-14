#!/usr/bin/env bash

monitor_install_tools() {
  log_step "安装监控与排障工具"
  pkg_install sysstat iotop iftop ncdu dstat strace tcpdump nload
  systemctl list-unit-files | grep -q '^sysstat\.service' && run systemctl enable --now sysstat || true
}

tools_install_modern_cli() {
  log_step "安装现代命令行工具"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install ripgrep fd-find bat fzf tree neovim
  else
    pkg_install ripgrep fd-find bat fzf tree neovim
  fi
}

tools_install_network_tools() {
  log_step "安装网络诊断工具"
  pkg_install mtr traceroute whois socat nmap iperf3 dnsutils tcpdump
}

tools_install_backup_tools() {
  log_step "安装备份/同步工具"
  pkg_install rclone restic borgbackup rsync
}

tools_install_security_tools() {
  log_step "安装安全常用工具"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install fail2ban ufw openssl ca-certificates
  else
    pkg_install fail2ban firewalld openssl ca-certificates
  fi
}

monitor_menu() {
  require_root
  detect_system
  clear_screen
  ui_panel_start "监控工具"
  ui_panel_line "[01] 安装 sysstat/iotop/iftop/ncdu/tcpdump/nload"
  ui_panel_line "[00] 返回"
  ui_panel_end
  printf '\n'
  local choice
  choice="$(ask_input "请选择" "01")"
  case "$choice" in
    1|01) monitor_install_tools ;;
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
    ui_panel_line "[01] 监控排障工具    sysstat/iotop/iftop/ncdu/tcpdump/nload"
    ui_panel_line "[02] 现代 CLI 工具   ripgrep/fd/bat/fzf/tree/neovim"
    ui_panel_line "[03] 网络诊断工具    mtr/traceroute/whois/socat/nmap/iperf3"
    ui_panel_line "[04] 备份同步工具    rclone/restic/borgbackup/rsync"
    ui_panel_line "[05] 安全常用工具    fail2ban/ufw/firewalld/openssl"
    ui_panel_line "[00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择" "00")"
    case "$choice" in
      1|01) monitor_install_tools ;;
      2|02) tools_install_modern_cli ;;
      3|03) tools_install_network_tools ;;
      4|04) tools_install_backup_tools ;;
      5|05) tools_install_security_tools ;;
      0|00) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}
