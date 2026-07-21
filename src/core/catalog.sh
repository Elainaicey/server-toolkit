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
    *) printf '%s' "$packages" ;;
  esac
}

catalog_installed() {
  local record="$1" _id _category _name _description packages handler
  IFS='|' read -r _id _category _name _description packages handler <<<"$record"
  case "$handler" in
    docker_official) command_exists docker ;;
    caddy_official) command_exists caddy ;;
    "") package_installed "$packages" ;;
    *) return 1 ;;
  esac
}

catalog_installed_version() {
  local record="$1" package version
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
  local package
  package="$(catalog_primary_package "$1")"
  local candidate
  candidate="$(package_candidate_version "$package")"
  [[ "$candidate" == "(none)" ]] && candidate=""
  printf '%s' "${candidate:-—}"
}

catalog_has_update() {
  local package
  catalog_installed "$1" || return 1
  package="$(catalog_primary_package "$1")"
  package_has_update "$package"
}

catalog_state() {
  local record="$1"
  if ! catalog_installed "$record"; then
    printf 'absent'
  elif catalog_has_update "$record"; then
    printf 'update'
  else
    printf 'current'
  fi
}

catalog_state_badge() {
  case "$1" in
    absent) ui_badge "未安装" "$MUTED" ;;
    update) ui_badge "可更新" "$YELLOW" ;;
    current) ui_badge "已是最新" "$GREEN" ;;
    *) ui_badge "未知" "$MUTED" ;;
  esac
}

catalog_statistics() {
  local record package total=0 installed=0 updates=0
  local -A upgradable=()
  if command_exists apt; then
    while IFS= read -r package; do
      [[ -n "$package" ]] && upgradable["$package"]=1
    done < <(apt list --upgradable 2>/dev/null | sed '1d;s#/.*##')
  fi
  while IFS= read -r record; do
    total=$((total + 1))
    if catalog_installed "$record"; then
      installed=$((installed + 1))
      package="$(catalog_primary_package "$record")"
      [[ -n "${upgradable[$package]:-}" ]] && updates=$((updates + 1))
    fi
  done < <(catalog_rows)
  printf '%s|%s|%s' "$total" "$installed" "$updates"
}

catalog_print_record() {
  local record="$1" id category name description packages handler state installed candidate
  IFS='|' read -r id category name description packages handler <<<"$record"
  state="$(catalog_state "$record")"
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  printf '  %b›%b %b' "$MAGENTA" "$NC" "$CYAN$BOLD"
  ui_pad "$id" 20
  printf '%b%b' "$NC" "$BLUE$BOLD"
  ui_pad "$name" 22
  printf '%b\n' "$(catalog_state_badge "$state")"
  printf '    %b%s%b\n' "$MUTED" "$description" "$NC"
  if [[ "$state" == "update" ]]; then
    printf '    %b版本%b  %b%s%b %b→%b %b%s%b\n' "$BLUE" "$NC" "$WHITE" "$installed" "$NC" "$MAGENTA" "$NC" "$YELLOW" "$candidate" "$NC"
  elif [[ "$state" == "current" ]]; then
    printf '    %b版本%b  %b%s%b\n' "$BLUE" "$NC" "$GREEN" "$installed" "$NC"
  else
    printf '    %b仓库版本%b  %b%s%b\n' "$BLUE" "$NC" "$WHITE" "$candidate" "$NC"
  fi
}

catalog_print() {
  local query="${1:-}" record category last_category="" count=0
  while IFS= read -r record; do
    IFS='|' read -r _ category _ <<<"$record"
    if [[ "$category" != "$last_category" ]]; then
      [[ -z "$last_category" ]] || printf '\n'
      ui_section "$category" "accent"
      last_category="$category"
    fi
    catalog_print_record "$record"
    count=$((count + 1))
  done < <(catalog_rows "$query")
  (( count > 0 )) || { warn "没有找到与 '$query' 匹配的软件。"; return 1; }
}

catalog_print_category() {
  local category="$1" record count=0
  while IFS= read -r record; do
    catalog_print_record "$record"
    count=$((count + 1))
  done < <(catalog_category_rows "$category")
  (( count > 0 )) || { warn "分类 '$category' 中没有软件。"; return 1; }
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
  ui_page "安装软件 / $name" "$id · $category"
  ui_panel_begin "变更摘要"
  ui_panel_kv "软件" "$name" "$CYAN"
  ui_panel_kv "说明" "$description"
  source_label="系统软件仓库"
  [[ -z "$handler" ]] || source_label="官方软件仓库"
  ui_panel_kv "来源" "$source_label"
  ui_panel_kv "目标版本" "$(catalog_candidate_version "$record")" "$GREEN"
  [[ -z "$packages" ]] || ui_panel_kv "系统包" "$packages"
  ui_panel_end
  confirm "确认安装 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_install_docker ;;
    caddy_official) software_install_caddy ;;
    "") package_install "$packages" ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-install id=$id"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "$name 安装预览完成。"; else ui_success "$name 安装完成。"; fi
}

catalog_update() {
  local id="$1" record _id category name description packages handler installed candidate
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" || { warn "$name 尚未安装，请先执行安装。"; return 1; }
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  ui_page "检查更新 / $name" "$id · $category"
  ui_panel_begin "本地索引"
  ui_panel_kv "当前版本" "$installed" "$WHITE"
  ui_panel_kv "候选版本" "$candidate" "$YELLOW"
  ui_panel_end
  ui_note "候选版本来自本机 APT 索引；更新前会先刷新仓库元数据。"
  confirm "刷新软件索引并检查 $name？" || return 0
  require_root
  package_invalidate_index
  package_update_index
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  ui_page "更新软件 / $name" "$id · $category"
  ui_panel_begin "最新版本信息"
  ui_panel_kv "当前版本" "$installed" "$WHITE"
  ui_panel_kv "候选版本" "$candidate" "$YELLOW"
  ui_panel_end
  if ! catalog_has_update "$record"; then
    ui_success "$name 已经是当前软件仓库中的最新版本。"
    return 0
  fi
  confirm "将 $name 更新到 $candidate？" || { warn "已取消。"; return 0; }
  case "$handler" in
    docker_official) software_update_docker ;;
    caddy_official) software_update_caddy ;;
    "") package_upgrade "$packages" ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-update id=$id from=$installed to=$candidate"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "$name 更新预览完成。"; else ui_success "$name 已更新。"; fi
}

catalog_remove() {
  local id="$1" record _id category name description packages handler
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" || { info "$name 未安装。"; return 0; }
  ui_page "移除软件 / $name" "$id · $category"
  ui_panel_begin "变更摘要"
  ui_panel_kv "软件" "$name" "$CYAN"
  ui_panel_kv "当前版本" "$(catalog_installed_version "$record")"
  ui_panel_kv "系统包" "${packages:-由官方安装器管理}"
  ui_panel_end
  ui_danger "只移除软件包，不删除它的数据目录和配置文件。"
  confirm "确认移除 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_remove_docker ;;
    caddy_official) software_remove_caddy ;;
    "") package_remove "$packages" ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-remove id=$id"
  ui_success "$name 移除完成。"
}

catalog_item_menu() {
  local id="$1" record _id category name description packages handler choice state source_label installed candidate
  record="$(catalog_record "$id")" || return 1
  IFS='|' read -r _id category name description packages handler <<<"$record"
  while true; do
    state="$(catalog_state "$record")"
    installed="$(catalog_installed_version "$record")"
    candidate="$(catalog_candidate_version "$record")"
    source_label="系统软件仓库"
    if [[ -n "$handler" ]]; then source_label="官方软件仓库"; fi
    if [[ "$handler" == "docker_official" ]] && package_installed docker.io; then source_label="系统软件仓库（现有安装）"; fi
    ui_page "软件管理 / $name" "$id · $category"
    ui_panel_begin "软件信息"
    ui_panel_kv "状态" "$(catalog_state_badge "$state")"
    ui_panel_kv "当前版本" "$installed"
    ui_panel_kv "仓库候选版本" "$candidate" "$CYAN"
    ui_panel_kv "说明" "$description"
    ui_panel_kv "来源" "$source_label"
    ui_panel_kv "系统包" "${packages:-由官方安装器管理}"
    ui_panel_end
    ui_section "可用操作" "primary"
    if [[ "$state" == "absent" ]]; then
      ui_action 1 "安装" "success" "安装候选版本 $candidate"
      ui_action 2 "更新" "disabled" "需要先安装"
      ui_action 3 "移除" "disabled" "当前未安装"
    else
      ui_action 1 "安装" "disabled" "已经安装"
      if [[ "$state" == "update" ]]; then
        ui_action 2 "更新" "warning" "$installed → $candidate"
      else
        ui_action 2 "检查更新" "action" "刷新索引并重新检查"
      fi
      ui_action 3 "移除" "danger" "保留配置和业务数据"
    fi
    ui_action 0 "返回软件中心" "muted"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1)
        if [[ "$state" == "absent" ]]; then catalog_install "$id" || true; else warn "$name 已经安装。"; fi
        pause
        ;;
      2)
        if [[ "$state" != "absent" ]]; then catalog_update "$id" || true; else warn "请先安装 $name。"; fi
        pause
        ;;
      3)
        if [[ "$state" != "absent" ]]; then catalog_remove "$id" || true; else warn "$name 尚未安装。"; fi
        pause
        ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

catalog_open_prompt() {
  local input
  input="$(read_input "软件 ID；输入 0 返回" "0")"
  [[ "$input" == "0" ]] && return 0
  if catalog_record "$input" >/dev/null 2>&1; then
    catalog_item_menu "$input"
  else
    warn "未知软件 ID：$input"
    pause
  fi
}

catalog_categories_view() {
  local entries=() category count choice index selected
  mapfile -t entries < <(catalog_categories)
  while true; do
    ui_page "软件管理 / 分类浏览" "按用途浏览 ${#entries[@]} 个分类"
    ui_section "软件分类" "primary"
    for index in "${!entries[@]}"; do
      IFS='|' read -r category count <<<"${entries[$index]}"
      ui_item "$((index + 1))" "$category" "$count 个软件"
    done
    ui_action 0 "返回软件中心" "muted"
    choice="$(read_input "请选择分类" "0")"
    [[ "$choice" == "0" ]] && return 0
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#entries[@]} )); then
      warn "无效分类编号：$choice"
      pause
      continue
    fi
    selected="${entries[$((choice - 1))]}"
    IFS='|' read -r category count <<<"$selected"
    ui_page "软件管理 / $category" "$count 个独立软件 · 输入精确 ID 进入管理"
    catalog_print_category "$category"
    catalog_open_prompt
  done
}

catalog_installed_view() {
  local record count
  while true; do
    ui_page "软件管理 / 已安装" "仅显示软件目录中已经安装的条目"
    count=0
    while IFS= read -r record; do
      if catalog_installed "$record"; then
        catalog_print_record "$record"
        count=$((count + 1))
      fi
    done < <(catalog_rows)
    if (( count == 0 )); then
      ui_empty "软件目录中暂未检测到已安装条目"
      pause
      return 0
    fi
    ui_note "共检测到 $count 个已安装条目；输入软件 ID 可更新或移除。"
    catalog_open_prompt
  done
}

catalog_updates_view() {
  local record count=0 input
  while true; do
    ui_page "软件管理 / 可用更新" "仅显示软件目录中已安装且有新版本的条目"
    count=0
    while IFS= read -r record; do
      if catalog_has_update "$record"; then
        catalog_print_record "$record"
        count=$((count + 1))
      fi
    done < <(catalog_rows)
    (( count > 0 )) || ui_success "目录中的已安装软件均为最新版本。"
    ui_note "输入软件 ID 查看详情；本页面不会自动批量更新系统。"
    input="$(read_input "软件 ID；输入 0 返回" "0")"
    [[ "$input" == "0" ]] && return 0
    if catalog_record "$input" >/dev/null 2>&1; then catalog_item_menu "$input"; else warn "未知软件 ID：$input"; pause; fi
  done
}

catalog_refresh_index() {
  ui_page "软件管理 / 刷新索引" "从已配置的软件仓库获取最新版本元数据"
  confirm "现在刷新 APT 软件索引？" || return 0
  require_root
  package_invalidate_index
  package_update_index
  ui_success "软件索引刷新完成。"
}

software_catalog_menu() {
  local input="" query="" stats total installed updates
  while true; do
    stats="$(catalog_statistics)"
    IFS='|' read -r total installed updates <<<"$stats"
    ui_page "软件管理" "独立软件的搜索、版本检查、安装、更新与移除"
    ui_stats "目录" "$total" "已安装" "$installed" "可更新" "$updates"
    ui_section "快捷操作" "primary"
    ui_action A "按分类浏览" "action" "在分类内查看版本、状态与可用操作"
    ui_action I "仅看已安装" "success" "快速进入已安装软件的更新与移除"
    ui_action U "查看可用更新" "warning" "只列出可更新条目"
    ui_action R "刷新软件索引" "accent" "从已配置仓库获取最新元数据"
    ui_section "搜索软件" "accent"
    ui_context "输入精确 ID 打开详情，或输入名称、分类、用途进行搜索。"
    if [[ -n "$query" ]]; then
      printf '\n'
      catalog_print "$query" || true
    else
      ui_empty "示例：python、网络、备份、nginx、docker"
    fi
    printf '\n'
    input="$(read_input "搜索 / ID / A / I / U / R；输入 0 返回" "0")"
    case "$input" in
      0) return 0 ;;
      A|a|all) query=""; catalog_categories_view ;;
      I|i|installed) catalog_installed_view ;;
      U|u) catalog_updates_view ;;
      R|r) catalog_refresh_index || true; pause ;;
      "") ;;
      *)
        if catalog_record "$input" >/dev/null 2>&1; then catalog_item_menu "$input"; else query="$input"; fi
        ;;
    esac
  done
}
