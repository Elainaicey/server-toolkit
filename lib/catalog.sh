#!/usr/bin/env bash

CATALOG_FILE="${SERVER_TOOLKIT_CATALOG_FILE:-$ROOT_DIR/catalog/packages.tsv}"

catalog_require_file() {
  [[ -r "$CATALOG_FILE" ]] || die "软件目录不可读：$CATALOG_FILE"
}

catalog_categories() {
  cat <<'CATEGORIES'
basic|基础工具
cli|现代 CLI
network|网络诊断
monitor|监控排障
backup|备份同步
security|安全工具
build|编译依赖
runtime|开发运行时
service|服务与数据库
CATEGORIES
}

catalog_category_name() {
  local wanted="$1"
  local id name
  while IFS='|' read -r id name; do
    [[ "$id" == "$wanted" ]] && { printf '%s' "$name"; return 0; }
  done < <(catalog_categories)
  return 1
}

catalog_rows() {
  local category="${1:-}"
  catalog_require_file
  if [[ -n "$category" ]]; then
    awk -F '|' -v category="$category" '!/^#/ && NF >= 5 && $2 == category' "$CATALOG_FILE"
  else
    awk -F '|' '!/^#/ && NF >= 5' "$CATALOG_FILE"
  fi
}

catalog_record() {
  local wanted="$1"
  catalog_require_file
  awk -F '|' -v wanted="$wanted" '!/^#/ && NF >= 5 && $1 == wanted { print; found=1; exit } END { if (!found) exit 1 }' "$CATALOG_FILE"
}

catalog_packages_for_record() {
  local record="$1"
  local _id _category _description debian_packages rhel_packages
  IFS='|' read -r _id _category _description debian_packages rhel_packages <<< "$record"
  case "$OS_FAMILY" in
    debian) printf '%s' "$debian_packages" ;;
    rhel) printf '%s' "$rhel_packages" ;;
    *) return 1 ;;
  esac
}

catalog_item_installed() {
  local record="$1"
  local packages package_array=() pkg
  packages="$(catalog_packages_for_record "$record")"
  [[ -n "$packages" ]] || return 1
  local old_ifs="$IFS"
  IFS=' ' read -r -a package_array <<< "$packages"
  IFS="$old_ifs"
  for pkg in "${package_array[@]}"; do
    pkg_installed "$pkg" || return 1
  done
}

catalog_print() {
  local filter="${1:-}"
  local id category description debian_packages rhel_packages category_label status
  local found=0
  printf '%-18s %-12s %-8s %s\n' "ID" "分类" "状态" "说明"
  printf '%-18s %-12s %-8s %s\n' "------------------" "------------" "--------" "------------------------------"
  while IFS='|' read -r id category description debian_packages rhel_packages; do
    if [[ -n "$filter" && "$category" != "$filter" && "$id" != *"$filter"* && "$description" != *"$filter"* ]]; then
      continue
    fi
    found=1
    category_label="$(catalog_category_name "$category" 2>/dev/null || printf '%s' "$category")"
    if [[ -z "$(catalog_packages_for_record "$id|$category|$description|$debian_packages|$rhel_packages")" ]]; then
      status="不支持"
    elif catalog_item_installed "$id|$category|$description|$debian_packages|$rhel_packages"; then
      status="已安装"
    else
      status="未安装"
    fi
    printf '%-18s %-12s %-8s %s\n' "$id" "$category_label" "$status" "$description"
  done < <(catalog_rows)
  [[ "$found" -eq 1 ]] || { log_warn "没有匹配的软件项：$filter"; return 1; }
}

catalog_install_items() {
  local ids=("$@")
  local id record packages old_ifs
  local package_array=()
  local failures=0
  ((${#ids[@]} > 0)) || { log_warn "没有指定要安装的软件项。"; return 1; }

  for id in "${ids[@]}"; do
    [[ -n "$id" ]] || continue
    if ! record="$(catalog_record "$id")"; then
      log_warn "软件目录中没有 '$id'；可运行 serverctl list 查询。"
      failures=$((failures + 1))
      continue
    fi
    packages="$(catalog_packages_for_record "$record")"
    if [[ -z "$packages" ]]; then
      log_warn "'$id' 暂不支持当前系统（${OS_ID:-$OS_FAMILY}）。"
      failures=$((failures + 1))
      continue
    fi
    package_array=()
    old_ifs="$IFS"
    IFS=' ' read -r -a package_array <<< "$packages"
    IFS="$old_ifs"
    log_step "安装 $id"
    if ! pkg_install_exact "${package_array[@]}"; then
      failures=$((failures + 1))
    fi
  done
  (( failures == 0 ))
}

catalog_validate_items() {
  local id record packages
  local failures=0
  for id in "$@"; do
    if ! record="$(catalog_record "$id")"; then
      log_warn "软件目录中没有 '$id'；可运行 serverctl list 查询。"
      failures=$((failures + 1))
      continue
    fi
    packages="$(catalog_packages_for_record "$record")"
    if [[ -z "$packages" ]]; then
      log_warn "'$id' 暂不支持当前系统（${OS_ID:-$OS_FAMILY}）。"
      failures=$((failures + 1))
    fi
  done
  (( failures == 0 ))
}

catalog_any_missing() {
  local id record
  for id in "$@"; do
    record="$(catalog_record "$id")" || return 0
    catalog_item_installed "$record" || return 0
  done
  return 1
}

catalog_install_bundle() {
  local bundle="$1"
  case "$bundle" in
    basic) catalog_install_items ca-certificates curl wget git jq vim unzip zip xz htop tmux lsof rsync sudo bash-completion ;;
    cli) catalog_install_items ripgrep fd bat fzf tree neovim ;;
    build) catalog_install_items build-essential cmake ninja pkg-config autotools ssl-dev ffi-dev zlib-dev ;;
    proxy) catalog_install_items ca-certificates curl wget socat openssl qrencode unzip jq ;;
    monitor) catalog_install_items sysstat iotop iftop ncdu dstat strace tcpdump nload ;;
    network) catalog_install_items mtr traceroute whois socat nmap iperf3 dnsutils tcpdump ;;
    backup) catalog_install_items rclone restic borgbackup rsync ;;
    security) catalog_install_items fail2ban openssl ca-certificates "$([[ "$OS_FAMILY" == "debian" ]] && printf ufw || printf firewalld)" ;;
    *) log_warn "未知软件集合：$bundle"; return 1 ;;
  esac
}

catalog_category_menu() {
  local category="$1"
  local title id row input token old_ifs
  local rows=() ids=() selected=()
  title="$(catalog_category_name "$category" 2>/dev/null || printf '%s' "$category")"
  mapfile -t rows < <(catalog_rows "$category")
  ((${#rows[@]} > 0)) || { log_warn "分类中没有软件项：$category"; return 1; }

  clear_screen
  ui_panel_start "$title · 单项安装"
  local i=0 description status
  for row in "${rows[@]}"; do
    IFS='|' read -r id _ description _ _ <<< "$row"
    ids+=("$id")
    status=""
    catalog_item_installed "$row" && status=" · 已安装"
    printf -v token '%02d' "$((i + 1))"
    ui_panel_line "[$token] $id$status — $description"
    i=$((i + 1))
  done
  ui_panel_rule
  ui_panel_line "输入编号或 ID，可用逗号/空格多选；all 安装本分类全部；00 返回"
  ui_panel_end
  printf '\n'
  input="$(ask_input "请选择" "00")"
  [[ "$input" == "0" || "$input" == "00" ]] && return 0
  if [[ "$input" == "all" ]]; then
    selected=("${ids[@]}")
  else
    input="${input//,/ }"
    old_ifs="$IFS"
    IFS=' ' read -r -a selected <<< "$input"
    IFS="$old_ifs"
    local normalized=() index
    for token in "${selected[@]}"; do
      [[ -n "$token" ]] || continue
      if [[ "$token" =~ ^[0-9]+$ ]]; then
        index=$((10#$token - 1))
        if (( index < 0 || index >= ${#ids[@]} )); then
          log_warn "编号超出范围：$token"
          continue
        fi
        normalized+=("${ids[$index]}")
      else
        normalized+=("$token")
      fi
    done
    selected=("${normalized[@]}")
  fi
  ((${#selected[@]} > 0)) || { log_warn "没有有效选择。"; return 1; }
  if ! catalog_validate_items "${selected[@]}"; then
    log_warn "选择中含有无效或不受支持的软件项，未执行安装。"
    return 0
  fi
  if catalog_any_missing "${selected[@]}"; then
    pkg_update_index
  fi
  if ! catalog_install_items "${selected[@]}"; then
    log_warn "部分软件项安装失败，请查看上方输出和日志。"
  fi
  return 0
}

catalog_menu() {
  while true; do
    clear_screen
    ui_panel_start "按单项选择软件"
    ui_panel_line "[01] 基础工具        [02] 现代 CLI"
    ui_panel_line "[03] 网络诊断        [04] 监控排障"
    ui_panel_line "[05] 备份同步        [06] 安全工具"
    ui_panel_line "[07] 编译依赖        [08] 开发运行时"
    ui_panel_line "[09] 服务与数据库    [00] 返回"
    ui_panel_end
    printf '\n'
    local choice
    choice="$(ask_input "请选择分类" "00")"
    case "$choice" in
      1|01) catalog_category_menu basic ;;
      2|02) catalog_category_menu cli ;;
      3|03) catalog_category_menu network ;;
      4|04) catalog_category_menu monitor ;;
      5|05) catalog_category_menu backup ;;
      6|06) catalog_category_menu security ;;
      7|07) catalog_category_menu build ;;
      8|08) catalog_category_menu runtime ;;
      9|09) catalog_category_menu service ;;
      0|00) break ;;
      *) log_warn "未知选项：$choice" ;;
    esac
    [[ "$choice" == "0" || "$choice" == "00" ]] || pause
  done
}
