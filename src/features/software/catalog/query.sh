#!/usr/bin/env bash

SOFTWARE_CATALOG="${SERVER_TOOLKIT_CATALOG:-$CONFIG_DIR/software.tsv}"

catalog_prompt_provider() {
  case "$1" in
    starship_prompt) printf 'starship' ;;
    oh_my_posh_prompt) printf 'oh-my-posh' ;;
    spaceship_prompt) printf 'spaceship' ;;
    *) return 1 ;;
  esac
}
catalog_source_kind() {
  local record="$1" _id _category _name _description _packages handler
  IFS='|' read -r _id _category _name _description _packages handler <<<"$record"
  case "$handler" in
    official_release) printf 'official-release' ;;
    docker_official|caddy_official) printf 'official-repository' ;;
    oh_my_zsh|spaceship_prompt) printf 'official-git' ;;
    starship_prompt|oh_my_posh_prompt) printf 'official-installer' ;;
    "") printf 'distribution' ;;
    *) printf 'other' ;;
  esac
}

catalog_source_label() {
  local record="$1" id _category _name _description packages handler
  IFS='|' read -r id _category _name _description packages handler <<<"$record"
  case "$handler" in
    official_release)
      if software_release_managed "$id"; then
        printf '项目官方 GitHub Release'
      elif [[ -n "$packages" ]] && package_installed "$packages"; then
        printf 'Debian / Ubuntu 软件仓库'
      else
        printf '项目官方 GitHub Release（推荐）'
      fi
      ;;
    docker_official|caddy_official) printf '项目官方 APT 仓库' ;;
    oh_my_zsh|spaceship_prompt) printf '项目官方 Git 仓库' ;;
    starship_prompt|oh_my_posh_prompt) printf '项目官方安装渠道' ;;
    "") printf 'Debian / Ubuntu 软件仓库' ;;
    *) printf '专用安装器' ;;
  esac
}

catalog_rows() {
  local query="${1:-}"
  [[ -r "$SOFTWARE_CATALOG" ]] || die "软件目录不可读：$SOFTWARE_CATALOG"
  if [[ -z "$query" ]]; then
    awk -F '|' '!/^#/ && NF == 6' "$SOFTWARE_CATALOG"
  else
    awk -F '|' -v query="$query" 'BEGIN {query=tolower(query)} !/^#/ && NF==6 && index(tolower($1" "$2" "$3" "$4),query){print}' "$SOFTWARE_CATALOG"
  fi
}

catalog_category_rows() {
  local category="$1"
  [[ -r "$SOFTWARE_CATALOG" ]] || die "软件目录不可读：$SOFTWARE_CATALOG"
  awk -F '|' -v category="$category" '!/^#/ && NF==6 && $2==category {print}' "$SOFTWARE_CATALOG"
}

catalog_categories() {
  [[ -r "$SOFTWARE_CATALOG" ]] || die "软件目录不可读：$SOFTWARE_CATALOG"
  awk -F '|' '
    !/^#/ && NF==6 {
      if (!seen[$2]++) order[++total]=$2
      count[$2]++
    }
    END {
      for (i=1; i<=total; i++) print order[i] "|" count[order[i]]
    }
  ' "$SOFTWARE_CATALOG"
}

catalog_record() {
  awk -F '|' -v wanted="$1" '!/^#/ && NF==6 && $1==wanted {print; found=1; exit} END{if(!found)exit 1}' "$SOFTWARE_CATALOG"
}

catalog_primary_package() {
  local record="$1" _id _category _name _description packages handler
  IFS='|' read -r _id _category _name _description packages handler <<<"$record"
  case "$handler" in
    docker_official)
      if package_installed docker-ce; then printf 'docker-ce'
      elif package_installed docker.io; then printf 'docker.io'
      else printf 'docker-ce'
      fi
      ;;
    caddy_official) printf 'caddy' ;;
    oh_my_zsh) printf 'oh-my-zsh' ;;
    starship_prompt) printf 'starship' ;;
    oh_my_posh_prompt) printf 'oh-my-posh' ;;
    spaceship_prompt) printf 'spaceship' ;;
    *) printf '%s' "$packages" ;;
  esac
}

catalog_installed() {
  local record="$1" id _category _name _description packages handler
  IFS='|' read -r id _category _name _description packages handler <<<"$record"
  case "$handler" in
    docker_official) command_exists docker ;;
    caddy_official) command_exists caddy ;;
    oh_my_zsh) software_oh_my_zsh_installed ;;
    starship_prompt) software_prompt_installed starship ;;
    oh_my_posh_prompt) software_prompt_installed oh-my-posh ;;
    spaceship_prompt) software_prompt_installed spaceship ;;
    official_release)
      software_release_managed "$id" || { [[ -n "$packages" ]] && package_installed "$packages"; }
      ;;
    "") package_installed "$packages" ;;
    *) return 1 ;;
  esac
}

catalog_installed_version() {
  local record="$1" id _category _name _description _packages handler package version provider
  IFS='|' read -r id _category _name _description _packages handler <<<"$record"
  if [[ "$handler" == "official_release" ]] && software_release_managed "$id"; then
    version="$(software_release_version "$id")"
    printf '%s' "${version:-—}"
    return 0
  fi
  if [[ "$handler" == "oh_my_zsh" ]]; then
    version="$(software_oh_my_zsh_version)"
    printf '%s' "${version:-—}"
    return 0
  fi
  if provider="$(catalog_prompt_provider "$handler" 2>/dev/null)"; then
    version="$(software_prompt_version "$provider")"
    printf '%s' "${version:-—}"
    return 0
  fi
  package="$(catalog_primary_package "$record")"
  version="$(package_installed_version "$package")"
  if [[ -z "$version" ]]; then
    case "$package" in
      docker-ce) command_exists docker && version="$(docker --version 2>/dev/null | sed -E 's/^Docker version ([^,]+).*/\1/' || true)" ;;
      caddy) command_exists caddy && version="$(caddy version 2>/dev/null | awk '{print $1}' || true)" ;;
    esac
  fi
  printf '%s' "${version:-—}"
}

catalog_candidate_version() {
  local record="$1" id _category _name _description _packages handler package provider
  IFS='|' read -r id _category _name _description _packages handler <<<"$record"
  if [[ "$handler" == "official_release" ]]; then
    if software_release_managed "$id"; then
      printf '官方稳定版（按需检查）'
    elif [[ -n "$_packages" ]] && package_installed "$_packages"; then
      local distro_candidate
      distro_candidate="$(package_candidate_version "$_packages")"
      printf '%s' "${distro_candidate:-—}"
    else
      printf '官方最新稳定版'
    fi
    return 0
  fi
  if [[ "$handler" == "oh_my_zsh" ]]; then
    printf '官方 master 分支'
    return 0
  fi
  if catalog_prompt_provider "$handler" >/dev/null 2>&1; then
    printf '官方最新版本'
    return 0
  fi
  package="$(catalog_primary_package "$record")"
  local candidate
  candidate="$(package_candidate_version "$package")"
  [[ "$candidate" == "(none)" ]] && candidate=""
  printf '%s' "${candidate:-—}"
}

catalog_has_update() {
  local record="$1" id _category _name _description _packages handler package
  catalog_installed "$record" || return 1
  IFS='|' read -r id _category _name _description _packages handler <<<"$record"
  if [[ "$handler" == "official_release" ]]; then
    software_release_managed "$id" && return 1
    [[ -n "$_packages" ]] || return 1
    package_has_update "$_packages"
    return
  fi
  [[ "$handler" != "oh_my_zsh" ]] || return 1
  catalog_prompt_provider "$handler" >/dev/null 2>&1 && return 1
  package="$(catalog_primary_package "$record")"
  package_has_update "$package"
}

catalog_available() {
  local record="$1" id _category _name _description packages handler candidate
  IFS='|' read -r id _category _name _description packages handler <<<"$record"
  if [[ "$handler" == "official_release" ]]; then
    software_release_supported "$id" && return 0
    [[ -n "$packages" ]] || return 1
    candidate="$(package_candidate_version "$packages")"
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
    return
  fi
  [[ -z "$handler" ]] || return 0
  candidate="$(package_candidate_version "$packages")"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

catalog_state() {
  local record="$1" candidate="${2:-}" id _category _name _description _packages handler
  IFS='|' read -r id _category _name _description _packages handler <<<"$record"
  if catalog_installed "$record"; then
    if [[ "$handler" == "official_release" ]] && software_release_managed "$id"; then
      if software_release_integrity "$id"; then printf 'managed'; else printf 'damaged'; fi
      return 0
    fi
    if [[ "$handler" == "oh_my_zsh" ]] || catalog_prompt_provider "$handler" >/dev/null 2>&1; then
      printf 'managed'
      return 0
    fi
    if catalog_has_update "$record"; then printf 'update'; else printf 'current'; fi
  elif (( $# > 1 )); then
    if [[ -n "$candidate" && "$candidate" != "—" ]]; then printf 'absent'; else printf 'unavailable'; fi
  elif ! catalog_available "$record"; then
    printf 'unavailable'
  else
    printf 'absent'
  fi
}
