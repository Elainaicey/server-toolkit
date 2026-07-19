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
    ufw)
      if ! command_exists ufw; then
        pkg_update_index
        pkg_install_exact ufw
      fi
      ;;
    firewalld)
      if ! command_exists firewall-cmd; then
        pkg_update_index
        pkg_install_exact firewalld
      fi
      systemctl list-unit-files | grep -q '^firewalld\.service' && run systemctl enable --now firewalld || true
      ;;
  esac
  FIREWALL_BACKEND_READY=1
}

firewall_allow_port() {
  local port="$1"
  valid_port "$port" || { log_warn "端口无效：$port（有效范围 1-65535）"; return 1; }
  local backend
  backend="$(firewall_detect_backend)"
  firewall_install_backend
  case "$backend" in
    ufw) run ufw allow "${port}/tcp" ;;
    firewalld) run firewall-cmd --permanent --add-port="${port}/tcp"; run firewall-cmd --reload ;;
  esac
}

# 供 Web/SSH 等模块联动使用：只调整已经存在的防火墙，不为此额外安装防火墙。
firewall_allow_port_if_present() {
  local port="$1"
  valid_port "$port" || { log_warn "端口无效：$port（有效范围 1-65535）"; return 1; }
  local backend
  backend="$(firewall_detect_backend)"
  case "$backend" in
    ufw)
      if command_exists ufw; then
        run ufw allow "${port}/tcp"
      else
        log_info "未安装 UFW，跳过端口规则；如需防火墙请进入防火墙模块。"
      fi
      ;;
    firewalld)
      if command_exists firewall-cmd; then
        run firewall-cmd --permanent --add-port="${port}/tcp"
        run firewall-cmd --reload
      else
        log_info "未安装 firewalld，跳过端口规则；如需防火墙请进入防火墙模块。"
      fi
      ;;
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
  clear_screen
  ui_panel_start "防火墙管理"
  ui_panel_line "$(printf '%b当前状态%b  %s' "$DIM" "$NC" "$(detect_firewall_state)")"
  ui_panel_rule
  ui_panel_line "[01] 启用基础防火墙并保留 SSH 端口"
  ui_panel_line "[02] 放行 TCP 端口"
  ui_panel_line "[00] 返回"
  ui_panel_end
  printf '\n'
  local choice
  choice="$(ask_input "请选择" "00")"
  case "$choice" in
    1|01) firewall_enable_basic "$(ask_input "额外 TCP 端口，逗号分隔" "")" ;;
    2|02)
      local ports p ports_arr=()
      ports="$(ask_input "TCP 端口，逗号分隔" "80,443")"
      IFS=',' read -r -a ports_arr <<< "${ports// /}"
      for p in "${ports_arr[@]}"; do
        firewall_allow_port "$p" || true
      done
      ;;
    0|00) return 0 ;;
  esac
  pause
}
