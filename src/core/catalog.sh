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
  local record="$1" _id _category _name _description packages handler
  IFS='|' read -r _id _category _name _description packages handler <<<"$record"
  case "$handler" in
    docker_official) command_exists docker ;;
    caddy_official) command_exists caddy ;;
    oh_my_zsh) software_oh_my_zsh_installed ;;
    starship_prompt) software_prompt_installed starship ;;
    oh_my_posh_prompt) software_prompt_installed oh-my-posh ;;
    spaceship_prompt) software_prompt_installed spaceship ;;
    "") package_installed "$packages" ;;
    *) return 1 ;;
  esac
}

catalog_installed_version() {
  local record="$1" _id _category _name _description _packages handler package version provider
  IFS='|' read -r _id _category _name _description _packages handler <<<"$record"
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
  local record="$1" _id _category _name _description _packages handler package provider
  IFS='|' read -r _id _category _name _description _packages handler <<<"$record"
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
  local record="$1" _id _category _name _description _packages handler package
  catalog_installed "$record" || return 1
  IFS='|' read -r _id _category _name _description _packages handler <<<"$record"
  [[ "$handler" != "oh_my_zsh" ]] || return 1
  catalog_prompt_provider "$handler" >/dev/null 2>&1 && return 1
  package="$(catalog_primary_package "$record")"
  package_has_update "$package"
}

catalog_available() {
  local record="$1" _id _category _name _description packages handler candidate
  IFS='|' read -r _id _category _name _description packages handler <<<"$record"
  [[ -z "$handler" ]] || return 0
  candidate="$(package_candidate_version "$packages")"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

catalog_state() {
  local record="$1" candidate="${2:-}"
  if catalog_installed "$record"; then
    if catalog_has_update "$record"; then printf 'update'; else printf 'current'; fi
  elif (( $# > 1 )); then
    if [[ -n "$candidate" && "$candidate" != "—" ]]; then printf 'absent'; else printf 'unavailable'; fi
  elif ! catalog_available "$record"; then
    printf 'unavailable'
  else
    printf 'absent'
  fi
}

catalog_state_badge() {
  case "$1" in
    absent) ui_badge "未安装" "$MUTED" ;;
    unavailable) ui_badge "仓库不可用" "$RED" ;;
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
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  state="$(catalog_state "$record" "$candidate")"
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
  elif [[ "$state" == "unavailable" ]]; then
    printf '    %b可用性%b  %b当前系统软件源未提供此软件包%b\n' "$BLUE" "$NC" "$YELLOW" "$NC"
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
  local id="$1" record _id category name description packages handler source_label provider
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  if catalog_installed "$record"; then
    if provider="$(catalog_prompt_provider "$handler" 2>/dev/null)"; then
      software_prompt_active "$provider" && { info "$name 已经安装并处于启用状态。"; return 0; }
      ui_page "启用提示符 / $name" "$id · $category"
      ui_note "该操作只切换 Server Toolkit 托管的活动提示符，不卸载其他引擎。"
      confirm "将 $name 设为当前 Zsh 提示符？" || return 0
      require_root
      software_activate_prompt "$provider"
      audit "action=prompt-activate id=$id"
      ui_success "$name 已启用；重新进入 Zsh 后生效。"
      return 0
    fi
    info "$name 已经安装。"
    return 0
  fi
  catalog_available "$record" || { warn "当前系统软件源未提供 $name，请先检查软件源或系统版本。"; return 1; }
  ui_page "安装软件 / $name" "$id · $category"
  ui_panel_begin "变更摘要"
  ui_panel_kv "软件" "$name" "$CYAN"
  ui_panel_kv "说明" "$description"
  source_label="系统软件仓库"
  [[ -z "$handler" ]] || source_label="官方软件仓库"
  [[ "$handler" != "oh_my_zsh" ]] || source_label="Oh My Zsh 官方 Git 仓库"
  if catalog_prompt_provider "$handler" >/dev/null 2>&1; then source_label="项目官方发布渠道"; fi
  ui_panel_kv "来源" "$source_label"
  ui_panel_kv "目标版本" "$(catalog_candidate_version "$record")" "$GREEN"
  if [[ "$handler" == "oh_my_zsh" ]]; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "目标目录" "$(software_oh_my_zsh_path)"
    ui_panel_kv "必要依赖" "zsh + git"
  elif catalog_prompt_provider "$handler" >/dev/null 2>&1; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "配置文件" "$(software_target_home "$(software_target_user)")/.zshrc"
    ui_panel_kv "提示" "安装后会切换为当前提示符；其他已安装提示符保留"
  elif [[ -n "$packages" ]]; then
    ui_panel_kv "系统包" "$packages"
  fi
  ui_panel_end
  confirm "确认安装 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_install_docker ;;
    caddy_official) software_install_caddy ;;
    oh_my_zsh) software_install_oh_my_zsh ;;
    starship_prompt) software_install_starship ;;
    oh_my_posh_prompt) software_install_oh_my_posh ;;
    spaceship_prompt) software_install_spaceship ;;
    "") package_install "$packages" ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-install id=$id"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "$name 安装预览完成。"; else ui_success "$name 安装完成。"; fi
}

catalog_update() {
  local id="$1" record _id category name description packages handler installed candidate provider
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" || { warn "$name 尚未安装，请先执行安装。"; return 1; }
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  if provider="$(catalog_prompt_provider "$handler" 2>/dev/null)"; then
    ui_page "更新提示符 / $name" "$id · $category"
    ui_panel_begin "官方更新"
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "当前版本" "$installed" "$WHITE"
    ui_panel_kv "更新来源" "$candidate" "$YELLOW"
    ui_panel_end
    confirm "检查并更新 $name？" || return 0
    require_root
    software_update_prompt "$provider"
    audit "action=software-update id=$id from=$installed"
    ui_success "$name 已检查并更新。"
    return 0
  fi
  if [[ "$handler" == "oh_my_zsh" ]]; then
    ui_page "更新软件 / $name" "$id · $category"
    ui_panel_begin "官方 Git 更新"
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "当前提交" "$installed" "$WHITE"
    ui_panel_kv "跟踪分支" "$candidate" "$YELLOW"
    ui_panel_kv "目标目录" "$(software_oh_my_zsh_path)"
    ui_panel_end
    ui_note "更新将调用 Oh My Zsh 官方 tools/upgrade.sh，并拒绝来源不明的仓库。"
    confirm "检查并更新 $name？" || return 0
    require_root
    software_update_oh_my_zsh
    audit "action=software-update id=$id from=$installed"
    if [[ "$DRY_RUN" -eq 1 ]]; then info "$name 更新预览完成。"; else ui_success "$name 已检查并更新。"; fi
    return 0
  fi
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
    oh_my_zsh) software_update_oh_my_zsh ;;
    starship_prompt) software_update_prompt starship ;;
    oh_my_posh_prompt) software_update_prompt oh-my-posh ;;
    spaceship_prompt) software_update_prompt spaceship ;;
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
  if [[ "$handler" == "oh_my_zsh" ]]; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "目标目录" "$(software_oh_my_zsh_path)"
  elif catalog_prompt_provider "$handler" >/dev/null 2>&1; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "配置文件" "$(software_target_home "$(software_target_user)")/.zshrc"
  else
    ui_panel_kv "系统包" "${packages:-由官方安装器管理}"
  fi
  ui_panel_end
  if [[ "$handler" == "oh_my_zsh" ]]; then
    ui_danger "将移除官方框架目录和 Server Toolkit 托管的 .zshrc 配置块；保留其他用户配置、Zsh、Git 与默认 Shell。"
  elif catalog_prompt_provider "$handler" >/dev/null 2>&1; then
    ui_danger "只移除当前提示符的托管文件和活动配置块；其他提示符与用户配置保持不变。"
  else
    ui_danger "只移除软件包，不删除它的数据目录和配置文件。"
  fi
  confirm "确认移除 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_remove_docker ;;
    caddy_official) software_remove_caddy ;;
    oh_my_zsh) software_remove_oh_my_zsh ;;
    starship_prompt) software_remove_prompt starship ;;
    oh_my_posh_prompt) software_remove_prompt oh-my-posh ;;
    spaceship_prompt) software_remove_prompt spaceship ;;
    "") package_remove "$packages" ;;
    *) die "未知安装器：$handler" ;;
  esac
  audit "action=software-remove id=$id"
  ui_success "$name 移除完成。"
}

catalog_item_menu() {
  local id="$1" record _id category name description packages handler choice state source_label installed candidate provider
  record="$(catalog_record "$id")" || return 1
  IFS='|' read -r _id category name description packages handler <<<"$record"
  while true; do
    installed="$(catalog_installed_version "$record")"
    candidate="$(catalog_candidate_version "$record")"
    state="$(catalog_state "$record" "$candidate")"
    source_label="系统软件仓库"
    if [[ -n "$handler" ]]; then source_label="官方软件仓库"; fi
    if [[ "$handler" == "oh_my_zsh" ]]; then source_label="Oh My Zsh 官方 Git 仓库"; fi
    if catalog_prompt_provider "$handler" >/dev/null 2>&1; then source_label="项目官方发布渠道"; fi
    if [[ "$handler" == "docker_official" ]] && package_installed docker.io; then source_label="系统软件仓库（现有安装）"; fi
    ui_page "软件管理 / $name" "$id · $category"
    ui_panel_begin "软件信息"
    ui_panel_kv "状态" "$(catalog_state_badge "$state")"
    ui_panel_kv "当前版本" "$installed"
    ui_panel_kv "仓库候选版本" "$candidate" "$CYAN"
    ui_panel_kv "说明" "$description"
    ui_panel_kv "来源" "$source_label"
    if [[ "$handler" == "oh_my_zsh" ]]; then
      ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
      ui_panel_kv "目标目录" "$(software_oh_my_zsh_path)"
      ui_panel_kv "必要依赖" "zsh + git"
    elif catalog_prompt_provider "$handler" >/dev/null 2>&1; then
      ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
      ui_panel_kv "配置文件" "$(software_target_home "$(software_target_user)")/.zshrc"
      ui_panel_kv "切换规则" "同一时间只激活一个托管提示符"
    else
      ui_panel_kv "系统包" "${packages:-由官方安装器管理}"
    fi
    ui_panel_end
    ui_section "可用操作" "primary"
    provider="$(catalog_prompt_provider "$handler" 2>/dev/null || true)"
    if [[ "$state" == "unavailable" ]]; then
      ui_action 1 "安装" "disabled" "当前系统软件源未提供"
      ui_action 2 "更新" "disabled" "需要先安装"
      ui_action 3 "移除" "disabled" "当前未安装"
    elif [[ "$state" == "absent" ]]; then
      ui_action 1 "安装" "success" "安装候选版本 $candidate"
      ui_action 2 "更新" "disabled" "需要先安装"
      ui_action 3 "移除" "disabled" "当前未安装"
    else
      if [[ -n "$provider" ]] && ! software_prompt_active "$provider"; then
        ui_action 1 "启用" "success" "切换为当前 Zsh 提示符"
      elif [[ -n "$provider" ]]; then
        ui_action 1 "已启用" "disabled" "当前活动提示符"
      else
        ui_action 1 "安装" "disabled" "已经安装"
      fi
      if [[ -n "$provider" ]]; then
        ui_action 2 "检查更新" "action" "从项目官方来源安装最新版本"
      elif [[ "$state" == "update" ]]; then
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
        if [[ "$state" == "absent" ]]; then
          catalog_install "$id" || true
        elif [[ "$state" == "unavailable" ]]; then
          warn "当前系统软件源未提供 $name。"
        elif [[ -n "$provider" ]] && ! software_prompt_active "$provider"; then
          catalog_install "$id" || true
        else
          warn "$name 已经安装。"
        fi
        pause
        ;;
      2)
        if [[ "$state" != "absent" && "$state" != "unavailable" ]]; then catalog_update "$id" || true; else warn "请先安装 $name。"; fi
        pause
        ;;
      3)
        if [[ "$state" != "absent" && "$state" != "unavailable" ]]; then catalog_remove "$id" || true; else warn "$name 尚未安装。"; fi
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
