#!/usr/bin/env bash

docker_detect() {
  ui_panel_start "Docker 检测"
  if command_exists docker; then
    ui_panel_line "$(docker --version 2>/dev/null || echo Docker 已安装)"
    docker compose version >/dev/null 2>&1 && ui_panel_line "$(docker compose version 2>/dev/null)"
  else
    ui_panel_line "Docker 未安装"
  fi
  ui_panel_end
  printf '\n'
  if command_exists systemctl && [[ -d /run/systemd/system ]]; then
    systemctl status docker --no-pager 2>/dev/null | sed -n '1,8p' || true
  fi
}

docker_configure_daemon() {
  log_step "配置 Docker 日志限制"
  safe_mkdir /etc/docker
  backup_file /etc/docker/daemon.json
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 写入/更新 /etc/docker/daemon.json"
    return 0
  fi
  if [[ -s /etc/docker/daemon.json ]]; then
    if ! command_exists jq; then
      log_info "合并现有 Docker 配置需要 jq，正在单独安装。"
      pkg_update_index
      pkg_install_exact jq || { log_warn "无法安装 jq，已保留原 daemon.json。"; return 1; }
    fi
    if ! jq empty /etc/docker/daemon.json >/dev/null 2>&1; then
      log_warn "/etc/docker/daemon.json 不是有效 JSON，已保留原文件，请手动修复。"
      return 1
    fi
    local tmp
    tmp="$(mktemp)"
    if jq '. + {"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' /etc/docker/daemon.json > "$tmp"; then
      mv "$tmp" /etc/docker/daemon.json
      chmod 0644 /etc/docker/daemon.json
    else
      rm -f "$tmp"
      log_warn "合并 Docker 配置失败，已保留原文件。"
      return 1
    fi
  else
    cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
  fi
  systemctl list-unit-files | grep -q '^docker\.service' && run systemctl restart docker || true
}

docker_install_official() {
  require_root
  detect_system
  log_step "安装 Docker"
  if [[ "$OS_FAMILY" == "debian" && ( "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ) ]]; then
    pkg_update_index
    pkg_install ca-certificates curl gnupg
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[DRY-RUN] 配置 Docker 官方 apt 仓库"
    else
      install -m 0755 -d /etc/apt/keyrings
      local docker_gpg_tmp
      docker_gpg_tmp="$(mktemp)"
      if ! curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o "$docker_gpg_tmp"; then
        rm -f "$docker_gpg_tmp"
        log_warn "Docker 官方 GPG 下载失败，回退到发行版仓库包。"
        pkg_install docker.io docker-compose-plugin
        return 0
      fi
      backup_file /etc/apt/keyrings/docker.asc
      install -m 0644 "$docker_gpg_tmp" /etc/apt/keyrings/docker.asc
      rm -f "$docker_gpg_tmp"
      local codename="${OS_CODENAME:-}"
      [[ -n "$codename" ]] || { log_warn "无法识别发行版代号，回退到发行版仓库包。"; pkg_install docker.io docker-compose-plugin; return 0; }
      backup_file /etc/apt/sources.list.d/docker.sources
      cat > /etc/apt/sources.list.d/docker.sources <<DOCKER_APT
Types: deb
URIs: https://download.docker.com/linux/${OS_ID}
Suites: ${codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_APT
    fi
    pkg_invalidate_index
    pkg_update_index
    pkg_install_exact docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    pkg_update_index
    [[ "$PM" == "dnf" ]] && pkg_install dnf-plugins-core || pkg_install yum-utils
    local repo_os="centos"
    [[ "$OS_ID" == "fedora" ]] && repo_os="fedora"
    [[ "$OS_ID" == "rhel" ]] && repo_os="rhel"
    run "$PM" config-manager --add-repo "https://download.docker.com/linux/${repo_os}/docker-ce.repo" || true
    pkg_invalidate_index
    pkg_update_index
    pkg_install_exact docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  systemctl list-unit-files | grep -q '^docker\.service' && run systemctl enable --now docker || true
  docker_configure_daemon
}

docker_menu() {
  require_root
  detect_system
  clear_screen
  ui_panel_start "Docker 环境"
  if command_exists docker; then
    ui_panel_line "$(docker --version 2>/dev/null || echo Docker 已安装)"
    if docker compose version >/dev/null 2>&1; then
      ui_panel_line "$(docker compose version 2>/dev/null)"
    fi
  else
    ui_panel_line "Docker 未安装"
  fi
  ui_panel_rule
  ui_panel_line "[01] 安装 Docker 官方版"
  ui_panel_line "[02] 配置 Docker 日志限制"
  ui_panel_line "[03] 查看 Docker 检测详情"
  ui_panel_line "[00] 返回"
  ui_panel_end
  printf '\n'
  local choice
  choice="$(ask_input "请选择" "00")"
  case "$choice" in
    1|01) docker_install_official ;;
    2|02) docker_configure_daemon ;;
    3|03) docker_detect ;;
    0|00) return 0 ;;
  esac
  pause
}
