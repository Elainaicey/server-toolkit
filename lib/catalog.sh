#!/usr/bin/env bash

SOFTWARE_CATALOG="${SERVER_TOOLKIT_CATALOG:-$ROOT_DIR/catalog/software.tsv}"

catalog_rows() {
  local query="${1:-}"
  [[ -r "$SOFTWARE_CATALOG" ]] || die "软件目录不可读：$SOFTWARE_CATALOG"
  if [[ -z "$query" ]]; then
    awk -F '|' '!/^#/ && NF == 6' "$SOFTWARE_CATALOG"
  else
    awk -F '|' -v query="$query" '
      BEGIN { query=tolower(query) }
      !/^#/ && NF == 6 && index(tolower($1 " " $2 " " $3 " " $4), query) { print }
    ' "$SOFTWARE_CATALOG"
  fi
}

catalog_record() {
  local wanted="$1"
  awk -F '|' -v wanted="$wanted" '!/^#/ && NF == 6 && $1 == wanted { print; found=1; exit } END { if (!found) exit 1 }' "$SOFTWARE_CATALOG"
}

catalog_installed() {
  local record="$1"
  local _id _category _name _description packages handler
  IFS='|' read -r _id _category _name _description packages handler <<<"$record"
  case "$handler" in
    docker_official) command_exists docker ;;
    caddy_official) command_exists caddy ;;
    "")
      local package list=()
      local old_ifs="$IFS"
      IFS=' ' read -r -a list <<<"$packages"
      IFS="$old_ifs"
      for package in "${list[@]}"; do
        package_installed "$package" || return 1
      done
      ;;
    *) return 1 ;;
  esac
}

catalog_print() {
  local query="${1:-}"
  local id category name description packages handler last_category="" state count=0
  while IFS='|' read -r id category name description packages handler; do
    if [[ "$category" != "$last_category" ]]; then
      [[ -n "$last_category" ]] && printf '\n'
      printf '%b%s%b\n' "$BOLD" "$category" "$NC"
      last_category="$category"
    fi
    state=""
    catalog_installed "$id|$category|$name|$description|$packages|$handler" && state=" ${GREEN}✓${NC}"
    printf '  %-20s %s%b  %b%s%b\n' "$id" "$name" "$state" "$DIM" "$description" "$NC"
    count=$((count + 1))
  done < <(catalog_rows "$query")
  if (( count == 0 )); then
    warn "没有找到与 '$query' 匹配的软件。"
    return 1
  fi
}

catalog_install() {
  local id="$1"
  local record _id category name description packages handler
  if ! record="$(catalog_record "$id")"; then
    warn "软件目录中没有 '$id'。输入 serverctl list 查询可用 ID。"
    return 1
  fi
  IFS='|' read -r _id category name description packages handler <<<"$record"

  ui_header "安装 $name"
  ui_kv "软件 ID" "$id"
  ui_kv "说明" "$description"
  if [[ -n "$packages" ]]; then
    ui_kv "系统包" "$packages"
  else
    ui_kv "安装方式" "官方软件仓库"
  fi

  if catalog_installed "$record"; then
    info "$name 已经安装。"
    return 0
  fi
  confirm "确认安装 $name？" || { warn "已取消。"; return 0; }
  require_root

  case "$handler" in
    docker_official) software_install_docker ;;
    caddy_official) software_install_caddy ;;
    "")
      local list=()
      local old_ifs="$IFS"
      IFS=' ' read -r -a list <<<"$packages"
      IFS="$old_ifs"
      package_install "${list[@]}"
      ;;
    *) die "软件项 '$id' 的安装器无效：$handler" ;;
  esac
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "$name 安装预览完成。"
  else
    info "$name 安装完成。"
  fi
}

software_catalog_menu() {
  local query=""
  local input=""
  while true; do
    ui_clear
    ui_header "单项软件安装"
    printf '%b输入准确的软件 ID 直接安装；输入其他文字自动搜索；输入 all 显示全部；输入 0 返回。%b\n\n' "$DIM" "$NC"
    catalog_print "$query" || true
    printf '\n'
    input="$(read_input "软件 ID 或搜索" "0")"
    case "$input" in
      0) return 0 ;;
      all) query="" ;;
      "") ;;
      *)
        if catalog_record "$input" >/dev/null 2>&1; then
          catalog_install "$input" || true
          pause
        else
          query="$input"
        fi
        ;;
    esac
  done
}
