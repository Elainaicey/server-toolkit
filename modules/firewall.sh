#!/usr/bin/env bash

FIREWALL_BACKEND_READY=0

firewall_detect_backend() {
  if [[ "$OS_FAMILY" == "debian" ]]; then
    echo ufw
  else
    echo firewalld
  fi
}

firewall_install_backend() {
  [[ "$FIREWALL_BACKEND_READY" -eq 1 ]] && return 0
  local backend
  backend="$(firewall_detect_backend)"
  case "$backend" in
    ufw) command_exists ufw || pkg_install ufw ;;
    firewalld)
      command_exists firewall-cmd || pkg_install firewalld
      systemctl list-unit-files | grep -q '^firewalld\.service' && run systemctl enable --now firewalld || true
      ;;
  esac
  FIREWALL_BACKEND_READY=1
}

firewall_allow_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || { log_warn "端口无效：$port"; return 0; }
  local backend
  backend="$(firewall_detect_backend)"
  firewall_install_backend
  case "$backend" in
    ufw) run ufw allow "${port}/tcp" ;;
    firewalld) run firewall-cmd --permanent --add-port="${port}/tcp"; run firewall-cmd --reload ;;
  esac
}

firewall_enable_basic() {
  local ports_csv="${1:-}"
  firewall_install_backend
  firewall_allow_port "${SSH_PORT:-22}"
  if [[ -n "$ports_csv" ]]; then
    local ports=()
    IFS=',' read -r -a ports <<< "${ports_csv// /}"
    local p
    for p in "${ports[@]}"; do
      [[ -n "$p" ]] && firewall_allow_port "$p"
    done
  fi
  if [[ "$(firewall_detect_backend)" == "ufw" ]]; then
    run ufw default deny incoming
    run ufw default allow outgoing
    run ufw --force enable
    run ufw status verbose || true
  fi
}

firewall_menu() {
  require_root
  detect_system
  print_title "防火墙管理"
  echo "当前状态：$(detect_firewall_state)"
  echo "1) 启用基础防火墙并保留 SSH 端口"
  echo "2) 放行 TCP 端口"
  echo "0) 返回"
  local choice
  choice="$(ask_input "请选择" "0")"
  case "$choice" in
    1) firewall_enable_basic "$(ask_input "额外 TCP 端口，逗号分隔" "")" ;;
    2)
      local ports p
      ports="$(ask_input "TCP 端口，逗号分隔" "80,443")"
      IFS=',' read -r -a ports_arr <<< "${ports// /}"
      for p in "${ports_arr[@]}"; do firewall_allow_port "$p"; done
      ;;
  esac
  pause
}
