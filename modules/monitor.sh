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
  ask_yes_no "是否安装 sysstat/iotop/iftop/ncdu/tcpdump/nload？" "Y" && monitor_install_tools
  pause
}

tools_menu() {
  require_root
  detect_system
  while true; do
    clear_screen
    print_title "监控 / 排障 / 备份工具"
    cat <<'MENU'
1. 监控排障工具：sysstat/iotop/iftop/ncdu/tcpdump/nload
2. 现代 CLI 工具：ripgrep/fd/bat/fzf/tree/neovim
3. 网络诊断工具：mtr/traceroute/whois/socat/nmap/iperf3
4. 备份同步工具：rclone/restic/borgbackup/rsync
5. 安全常用工具：fail2ban/ufw/firewalld/openssl
0. 返回
MENU
    local choice
    choice="$(ask_input "请选择" "0")"
    case "$choice" in
      1) monitor_install_tools ;;
      2) tools_install_modern_cli ;;
      3) tools_install_network_tools ;;
      4) tools_install_backup_tools ;;
      5) tools_install_security_tools ;;
      0) break ;;
      *) log_warn "未知选项" ;;
    esac
    pause
  done
}
