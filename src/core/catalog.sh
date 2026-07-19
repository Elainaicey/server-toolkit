#!/usr/bin/env bash

SOFTWARE_CATALOG="${SERVER_TOOLKIT_CATALOG:-$CONFIG_DIR/software.tsv}"

catalog_rows() {
  local query="${1:-}"
  [[ -r "$SOFTWARE_CATALOG" ]] || die "软件目录不可读：$SOFTWARE_CATALOG"
  if [[ -z "$query" ]]; then
    awk -F '|' '!/^#/ && NF == 6' "$SOFTWARE_CATALOG"
  else
    awk -F '|' -v query="$query" 'BEGIN {query=tolower(query)} !/^#/ && NF==6 && index(tolower($1" "$2" "$3" "$4),query){print}' "$SOFTWARE_CATALOG"
  fi
}

catalog_record() { awk -F '|' -v wanted="$1" '!/^#/ && NF==6 && $1==wanted {print; found=1; exit} END{if(!found)exit 1}' "$SOFTWARE_CATALOG"; }

catalog_installed() {
  local record="$1" _id _category _name _description packages handler package
  local list=()
  IFS='|' read -r _id _category _name _description packages handler <<<"$record"
  case "$handler" in
    docker_official) command_exists docker ;;
    caddy_official) command_exists caddy ;;
    "")
      local old_ifs="$IFS"; IFS=' ' read -r -a list <<<"$packages"; IFS="$old_ifs"
      for package in "${list[@]}"; do package_installed "$package" || return 1; done
      ;;
    *) return 1 ;;
  esac
}

catalog_print() {
  local query="${1:-}" id category name description packages handler last_category="" state count=0
  while IFS='|' read -r id category name description packages handler; do
    if [[ "$category" != "$last_category" ]]; then
      [[ -z "$last_category" ]] || printf '\n'
      printf '%b%s%b\n' "$BOLD" "$category" "$NC"; last_category="$category"
    fi
    state="$(ui_badge "未安装" "$DIM")"
    catalog_installed "$id|$category|$name|$description|$packages|$handler" && state="$(ui_badge "已安装" "$GREEN")"
    printf '  %-20s %-18s %b\n' "$id" "$name" "$state"
    printf '  %b%s%b\n' "$DIM" "$description" "$NC"
    count=$((count + 1))
  done < <(catalog_rows "$query")
  (( count > 0 )) || { warn "没有找到与 '$query' 匹配的软件。"; return 1; }
}

catalog_packages() {
  local record="$1" _id _category _name _description packages _handler
  IFS='|' read -r _id _category _name _description packages _handler <<<"$record"
  printf '%s' "$packages"
}

catalog_install() {
  local id="$1" record _id category name description packages handler source_label
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" && { info "$name 已经安装。"; return 0; }
  ui_header "安装 $name"
  ui_kv "软件 ID" "$id"
  ui_kv "分类" "$category"
  ui_kv "说明" "$description"
  source_label="系统软件仓库"
  if [[ -n "$handler" ]]; then
    source_label="官方软件仓库"
  fi
  ui_kv "来源" "$source_label"
  [[ -z "$packages" ]] || ui_kv "系统包" "$packages"
  confirm "确认安装 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_install_docker ;;
    caddy_official) software_install_caddy ;;
    "")
      local list=() old_ifs="$IFS"
      IFS=' ' read -r -a list <<<"$packages"
      IFS="$old_ifs"
      package_install "${list[@]}"
      ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-install id=$id"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "$name 安装预览完成。"
  else
    info "$name 安装完成。"
  fi
}

catalog_remove() {
  local id="$1" record _id category name description packages handler
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" || { info "$name 未安装。"; return 0; }
  ui_header "移除 $name"
  ui_kv "软件 ID" "$id"
  ui_kv "分类" "$category"
  ui_kv "说明" "$description"
  warn "只移除软件包，不删除其数据目录和配置文件。"
  confirm "确认移除 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_remove_docker ;;
    caddy_official) software_remove_caddy ;;
    "")
      local list=() old_ifs="$IFS"
      IFS=' ' read -r -a list <<<"$packages"
      IFS="$old_ifs"
      package_remove "${list[@]}"
      ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-remove id=$id"
  info "$name 移除完成。"
}

catalog_item_menu() {
  local id="$1" record _id category name description packages handler choice status source_label
  record="$(catalog_record "$id")" || return 1
  IFS='|' read -r _id category name description packages handler <<<"$record"
  while true; do
    ui_clear; ui_header "$name"
    status="未安装"
    if catalog_installed "$record"; then
      status="已安装"
    fi
    ui_kv "状态" "$status"
    ui_kv "分类" "$category"
    ui_kv "说明" "$description"
    source_label="系统软件仓库"
    if [[ -n "$handler" ]]; then source_label="官方软件仓库"; fi
    ui_kv "来源" "$source_label"
    ui_kv "系统包" "${packages:-由官方安装器管理}"
    ui_item 1 "安装"
    ui_item 2 "移除"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) catalog_install "$id" || true; pause ;;
      2) catalog_remove "$id" || true; pause ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

software_catalog_menu() {
  local query="" input="" show_all=0 count
  while true; do
    ui_clear
    ui_header "软件管理"
    printf '%b输入准确 ID 查看软件；输入其他文字搜索；all 显示全部；0 返回。%b\n\n' "$DIM" "$NC"
    if [[ "$show_all" -eq 1 || -n "$query" ]]; then
      catalog_print "$query" || true
    else
      count="$(catalog_rows | wc -l | tr -d ' ')"
      ui_empty "目录中有 $count 个独立软件项。输入用途、名称或 ID 开始搜索。"
      ui_empty "例如：python、网络、备份、nginx、docker"
    fi
    printf '\n'
    input="$(read_input "软件 ID 或搜索" "0")"
    case "$input" in
      0) return 0 ;;
      all) query=""; show_all=1 ;;
      "") ;;
      *)
        if catalog_record "$input" >/dev/null 2>&1; then
          catalog_item_menu "$input"
        else
          query="$input"
          show_all=0
        fi
        ;;
    esac
  done
}
