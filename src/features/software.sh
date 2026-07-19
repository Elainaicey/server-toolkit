#!/usr/bin/env bash

software_install_docker() {
  local conflict conflict_list
  local conflicts=(docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc)
  local installed_conflicts=()
  for conflict in "${conflicts[@]}"; do
    if package_installed "$conflict"; then
      installed_conflicts+=("$conflict")
    fi
  done
  if ((${#installed_conflicts[@]} > 0)); then
    printf -v conflict_list '%s ' "${installed_conflicts[@]}"
    warn "检测到与 Docker 官方包冲突的软件：${conflict_list% }"
    confirm "先移除这些冲突包（不删除容器数据）？" || return 1
    package_remove "${installed_conflicts[@]}"
  fi
  info "准备 Docker 官方仓库。"
  package_install ca-certificates curl gnupg
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将配置 Docker 官方仓库。"
    package_invalidate_index
    package_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    return 0
  fi
  [[ -n "$OS_CODENAME" ]] || die "无法识别系统代号。"
  local key_tmp; key_tmp="$(mktemp)"
  curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" -o "$key_tmp" || { rm -f "$key_tmp"; die "下载 Docker 签名失败。"; }
  backup_file /etc/apt/keyrings/docker.asc; backup_file /etc/apt/sources.list.d/docker.sources
  install -d -m 0755 /etc/apt/keyrings
  install -m 0644 "$key_tmp" /etc/apt/keyrings/docker.asc; rm -f "$key_tmp"
  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$OS_ID
Suites: $OS_CODENAME
Components: stable
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  package_invalidate_index
  package_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  service_enable_now docker.service
}

software_remove_docker() {
  package_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

software_update_docker() {
  if package_installed docker.io && ! package_installed docker-ce; then
    package_upgrade docker.io
    return 0
  fi
  package_installed docker-ce || { warn "无法识别当前 Docker 的软件包来源。"; return 1; }
  local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
  local installed=() package
  for package in "${packages[@]}"; do
    package_installed "$package" && installed+=("$package")
  done
  ((${#installed[@]} > 0)) || { warn "没有检测到可更新的 Docker 官方组件。"; return 1; }
  apt_run install --only-upgrade -y "${installed[@]}"
}

software_install_caddy() {
  info "准备 Caddy 官方仓库。"
  package_install ca-certificates curl gnupg debian-keyring debian-archive-keyring
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将配置 Caddy 官方仓库。"; package_invalidate_index; package_install caddy; return 0; fi
  local key_source key_binary list_source
  key_source="$(mktemp)"; key_binary="$(mktemp)"; list_source="$(mktemp)"
  if ! curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key -o "$key_source" || \
     ! gpg --batch --yes --dearmor -o "$key_binary" "$key_source" || \
     ! curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o "$list_source"; then
    rm -f "$key_source" "$key_binary" "$list_source"; die "下载 Caddy 仓库配置失败。"
  fi
  backup_file /usr/share/keyrings/caddy-stable-archive-keyring.gpg; backup_file /etc/apt/sources.list.d/caddy-stable.list
  install -m 0644 "$key_binary" /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  install -m 0644 "$list_source" /etc/apt/sources.list.d/caddy-stable.list
  rm -f "$key_source" "$key_binary" "$list_source"
  package_invalidate_index; package_install caddy; service_enable_now caddy.service
}

software_remove_caddy() { package_remove caddy; }

software_update_caddy() { package_upgrade caddy; }
