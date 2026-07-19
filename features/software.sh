#!/usr/bin/env bash

software_install_docker() {
  info "准备 Docker 官方仓库。"
  package_install ca-certificates curl gnupg

  if [[ "$DRY_RUN" -eq 1 ]]; then
    backup_file /etc/apt/keyrings/docker.asc
    backup_file /etc/apt/sources.list.d/docker.sources
    info "将写入 Docker 官方仓库配置。"
    package_invalidate_index
    package_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    service_enable_now docker.service
    return 0
  fi

  local codename="$OS_CODENAME"
  [[ -n "$codename" ]] || die "无法识别系统代号，不能配置 Docker 官方仓库。"
  local key_tmp
  key_tmp="$(mktemp)"
  if ! curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" -o "$key_tmp"; then
    rm -f "$key_tmp"
    die "下载 Docker 仓库签名失败。"
  fi

  backup_file /etc/apt/keyrings/docker.asc
  backup_file /etc/apt/sources.list.d/docker.sources
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将写入 Docker 官方仓库配置。"
    rm -f "$key_tmp"
  else
    install -d -m 0755 /etc/apt/keyrings
    install -m 0644 "$key_tmp" /etc/apt/keyrings/docker.asc
    rm -f "$key_tmp"
    cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$OS_ID
Suites: $codename
Components: stable
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  fi

  package_invalidate_index
  package_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  service_enable_now docker.service
}

software_install_caddy() {
  info "准备 Caddy 官方仓库。"
  package_install ca-certificates curl gnupg debian-keyring debian-archive-keyring

  if [[ "$DRY_RUN" -eq 1 ]]; then
    backup_file /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    backup_file /etc/apt/sources.list.d/caddy-stable.list
    info "将写入 Caddy 官方仓库配置。"
    package_invalidate_index
    package_install caddy
    service_enable_now caddy.service
    return 0
  fi

  local key_source key_binary list_source
  key_source="$(mktemp)"
  key_binary="$(mktemp)"
  list_source="$(mktemp)"
  if ! curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key -o "$key_source" || \
     ! gpg --batch --yes --dearmor -o "$key_binary" "$key_source" || \
     ! curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o "$list_source"; then
    rm -f "$key_source" "$key_binary" "$list_source"
    die "下载 Caddy 仓库配置失败。"
  fi

  backup_file /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  backup_file /etc/apt/sources.list.d/caddy-stable.list
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将写入 Caddy 官方仓库配置。"
  else
    install -m 0644 "$key_binary" /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    install -m 0644 "$list_source" /etc/apt/sources.list.d/caddy-stable.list
  fi
  rm -f "$key_source" "$key_binary" "$list_source"

  package_invalidate_index
  package_install caddy
  service_enable_now caddy.service
}
