#!/usr/bin/env bash

web_detect_ports() {
  print_title "Web 端口检测"
  echo "80:  ${PORT_80:-free/unknown}"
  echo "443: ${PORT_443:-free/unknown}"
}

web_install_stack() {
  local stack="$1"
  detect_system
  case "$stack" in
    caddy)
      log_step "安装 Caddy"
      if [[ "$OS_FAMILY" == "debian" ]]; then
        pkg_install debian-keyring debian-archive-keyring apt-transport-https curl gnupg
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log_info "[DRY-RUN] 配置 Caddy 官方仓库"
        else
          curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o /tmp/caddy-stable.gpg.key || { pkg_install caddy; return 0; }
          gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg /tmp/caddy-stable.gpg.key || { rm -f /tmp/caddy-stable.gpg.key; pkg_install caddy; return 0; }
          rm -f /tmp/caddy-stable.gpg.key
          curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o /etc/apt/sources.list.d/caddy-stable.list || { pkg_install caddy; return 0; }
          chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
        fi
        pkg_update_index
      fi
      pkg_install caddy
      systemctl list-unit-files | grep -q '^caddy\.service' && run systemctl enable --now caddy || true
      firewall_allow_port 80
      firewall_allow_port 443
      ;;
    nginx)
      log_step "安装 Nginx"
      pkg_install nginx
      systemctl list-unit-files | grep -q '^nginx\.service' && run systemctl enable --now nginx || true
      firewall_allow_port 80
      firewall_allow_port 443
      ;;
    *) log_warn "未知 Web 环境：$stack" ;;
  esac
}

web_menu() {
  require_root
  detect_system
  web_detect_ports
  if [[ -n "$PORT_80$PORT_443" ]]; then
    log_warn "如果 80/443 已被占用，请确认只让一个 Web 服务监听公网端口。"
  fi
  echo "1) 安装 Caddy"
  echo "2) 安装 Nginx"
  echo "3) 不安装"
  local choice
  choice="$(ask_input "请选择" "3")"
  case "$choice" in
    1) web_install_stack caddy ;;
    2) web_install_stack nginx ;;
  esac
  pause
}
