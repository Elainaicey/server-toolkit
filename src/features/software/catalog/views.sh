#!/usr/bin/env bash

catalog_item_menu() {
  local id="$1" record _id category name description packages handler choice state source_label installed candidate provider
  record="$(catalog_record "$id")" || return 1
  IFS='|' read -r _id category name description packages handler <<<"$record"
  while true; do
    installed="$(catalog_installed_version "$record")"
    candidate="$(catalog_candidate_version "$record")"
    state="$(catalog_state "$record" "$candidate")"
    source_label="$(catalog_source_label "$record")"
    if [[ "$handler" == "docker_official" ]] && package_installed docker.io; then source_label="系统软件仓库（现有安装）"; fi
    ui_page "软件管理 / $name" "$id · $category"
    ui_panel_begin "软件信息"
    ui_panel_kv "状态" "$(catalog_state_badge "$state")"
    ui_panel_kv "当前版本" "$installed"
    ui_panel_kv "目标 / 候选版本" "$candidate" "$CYAN"
    ui_panel_kv "说明" "$description"
    ui_panel_kv "来源" "$source_label"
    if [[ "$handler" == "official_release" ]]; then
      ui_panel_kv "官方项目" "$(software_release_repository "$id")"
      ui_panel_kv "项目主页" "$(software_release_homepage "$id")"
      ui_panel_kv "命令路径" "$(software_release_target "$id")"
      if software_release_managed "$id"; then
        ui_panel_kv "完整性" "$(software_release_integrity "$id" && printf 'SHA-256 正常' || printf '异常')" \
          "$(software_release_integrity "$id" && printf '%s' "$GREEN" || printf '%s' "$RED")"
      else
        ui_panel_kv "完整性" "安装时校验 GitHub SHA-256 digest"
      fi
      [[ -z "$packages" ]] || ui_panel_kv "发行版备选" "$packages"
    elif [[ "$handler" == "oh_my_zsh" ]]; then
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
      elif [[ "$handler" == "official_release" ]] && software_release_managed "$id"; then
        ui_action 2 "检查官方更新" "action" "查询 latest stable Release 并验证 SHA-256"
      elif [[ "$state" == "update" ]]; then
        ui_action 2 "更新" "warning" "$installed → $candidate"
      else
        ui_action 2 "检查更新" "action" "刷新索引并重新检查"
      fi
      ui_action 3 "移除" "danger" "保留配置和业务数据"
    fi
    if [[ "$handler" == "official_release" ]]; then
      if [[ "$state" != "absent" && "$state" != "unavailable" && -n "$packages" ]]; then
        ui_action 4 "切换来源" "accent" "官方稳定版与发行版软件包之间切换"
      else
        ui_action 4 "切换来源" "disabled" "当前没有可切换的第二来源"
      fi
      if software_release_managed "$id"; then
        if [[ "$state" == "damaged" ]]; then
          ui_action 5 "修复官方安装" "danger" "备份现有命令并重新安装可信版本"
        else
          ui_action 5 "重新安装官方版" "warning" "重新下载、校验并部署当前最新稳定版"
        fi
      else
        ui_action 5 "修复官方安装" "disabled" "当前不由官方 Release 安装器管理"
      fi
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
      4)
        if [[ "$handler" == "official_release" && "$state" != "absent" && "$state" != "unavailable" && -n "$packages" ]]; then
          catalog_switch_source "$id" || true
        else
          warn "$name 当前没有可切换的第二来源。"
        fi
        pause
        ;;
      5)
        if [[ "$handler" == "official_release" ]] && software_release_managed "$id"; then
          ui_page "修复官方安装 / $name" "$id · 重新下载并验证官方稳定版"
          ui_danger "如命令完整性异常，现有文件会先备份，再由通过 SHA-256 校验的官方版本替换。"
          if confirm "重新安装 $name 的官方稳定版？"; then
            require_root
            if software_repair_release "$id"; then
              audit "action=software-release-repair id=$id"
              [[ "$DRY_RUN" -eq 1 ]] || ui_success "$name 官方安装已修复。"
            fi
          fi
        else
          warn "$name 当前不由官方 Release 安装器管理。"
        fi
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
    ui_page "软件管理 / 仓库更新" "显示 APT 索引中已安装且有新候选版本的条目"
    count=0
    while IFS= read -r record; do
      if catalog_has_update "$record"; then
        catalog_print_record "$record"
        count=$((count + 1))
      fi
    done < <(catalog_rows)
    (( count > 0 )) || ui_success "APT 管理的软件均为当前仓库候选版本。"
    ui_note "官方 Release 使用独立检查入口；本页面不会自动批量更新系统。"
    input="$(read_input "软件 ID；输入 0 返回" "0")"
    [[ "$input" == "0" ]] && return 0
    if catalog_record "$input" >/dev/null 2>&1; then catalog_item_menu "$input"; else warn "未知软件 ID：$input"; pause; fi
  done
}

catalog_source_rows() {
  local wanted="$1" record
  while IFS= read -r record; do
    [[ "$(catalog_source_kind "$record")" == "$wanted" ]] && printf '%s\n' "$record"
  done < <(catalog_rows)
}

catalog_sources_view() {
  local choice kind title record count input
  while true; do
    ui_page "软件管理 / 来源浏览" "按维护渠道查看软件，系统组件与上游工具采用不同策略"
    ui_section "来源类型" "primary"
    ui_action 1 "发行版软件仓库" "action" "Debian / Ubuntu 维护，系统兼容优先"
    ui_action 2 "项目官方 Release" "success" "独立 CLI · amd64/arm64 · SHA-256 校验"
    ui_action 3 "项目官方 APT 仓库" "accent" "Docker、Caddy 等长期运行服务"
    ui_action 4 "项目官方 Git 仓库" "action" "框架、主题与可追踪源码安装"
    ui_action 5 "项目官方安装渠道" "warning" "带来源验证的专用安装程序"
    ui_action 0 "返回软件中心" "muted"
    choice="$(read_input "请选择来源" "0")"
    case "$choice" in
      1) kind="distribution"; title="发行版软件仓库" ;;
      2) kind="official-release"; title="项目官方 Release" ;;
      3) kind="official-repository"; title="项目官方 APT 仓库" ;;
      4) kind="official-git"; title="项目官方 Git 仓库" ;;
      5) kind="official-installer"; title="项目官方安装渠道" ;;
      0) return 0 ;;
      *) warn "未知来源编号：$choice"; pause; continue ;;
    esac
    ui_page "软件来源 / $title" "输入精确 ID 可查看版本、完整性和来源切换能力"
    count=0
    while IFS= read -r record; do
      catalog_print_record "$record"
      count=$((count + 1))
    done < <(catalog_source_rows "$kind")
    (( count > 0 )) || ui_empty "该来源暂时没有软件条目"
    ui_note "共 $count 个条目；来源策略只影响所选软件，不会批量修改系统。"
    input="$(read_input "软件 ID；输入 0 返回来源列表" "0")"
    [[ "$input" == "0" ]] && continue
    if catalog_record "$input" >/dev/null 2>&1; then catalog_item_menu "$input"; else warn "未知软件 ID：$input"; pause; fi
  done
}

catalog_official_updates_view() {
  local interactive="${1:-1}" record id _category name _description _packages handler current latest input checked=0 updates=0 failed=0
  ui_page "软件管理 / 官方更新检查" "逐项查询已托管 CLI 的 latest stable Release，不自动安装"
  ui_note "只检查由 Server Toolkit 官方 Release 安装器管理的软件；GitHub API 可能需要数秒。"
  while IFS= read -r record; do
    IFS='|' read -r id _category name _description _packages handler <<<"$record"
    [[ "$handler" == "official_release" ]] || continue
    software_release_managed "$id" || continue
    checked=$((checked + 1))
    current="$(software_release_version "$id")"
    if ! software_release_load_latest "$id"; then
      printf '  %b×%b %-18s %b查询失败%b\n' "$RED" "$NC" "$id" "$RED" "$NC"
      failed=$((failed + 1))
    else
      latest="$SOFTWARE_RELEASE_LATEST_VERSION"
      if dpkg --compare-versions "$latest" gt "$current"; then
      printf '  %b↑%b %-18s %b%s%b %b→%b %b%s%b\n' \
        "$YELLOW" "$NC" "$id" "$WHITE" "$current" "$NC" "$MAGENTA" "$NC" "$YELLOW" "$latest" "$NC"
      updates=$((updates + 1))
      elif software_release_integrity "$id"; then
      printf '  %b✓%b %-18s %b%s · 已是最新%b\n' "$GREEN" "$NC" "$id" "$GREEN" "$current" "$NC"
      else
      printf '  %b!%b %-18s %b%s · 完整性异常%b\n' "$RED" "$NC" "$id" "$RED" "$current" "$NC"
      failed=$((failed + 1))
      fi
    fi
  done < <(catalog_rows)
  (( checked > 0 )) || ui_empty "尚未安装由官方 Release 管理的软件"
  ui_panel_begin "检查结果"
  ui_panel_kv "已检查" "$checked 项"
  ui_panel_kv "可更新" "$updates 项" "$YELLOW"
  ui_panel_kv "异常 / 失败" "$failed 项" "$([[ "$failed" -eq 0 ]] && printf '%s' "$GREEN" || printf '%s' "$RED")"
  ui_panel_end
  [[ "$interactive" -eq 1 ]] || return 0
  ui_note "输入软件 ID 可单独更新、修复或切换来源。"
  input="$(read_input "软件 ID；输入 0 返回" "0")"
  [[ "$input" == "0" ]] && return 0
  if catalog_record "$input" >/dev/null 2>&1; then catalog_item_menu "$input"; else warn "未知软件 ID：$input"; pause; fi
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
    ui_stats "目录" "$total" "已安装" "$installed" "仓库更新" "$updates"
    ui_section "快捷操作" "primary"
    ui_action A "按分类浏览" "action" "在分类内查看版本、状态与可用操作"
    ui_action I "仅看已安装" "success" "快速进入已安装软件的更新与移除"
    ui_action U "查看仓库更新" "warning" "只列出 APT 候选版本更新"
    ui_action O "检查官方更新" "success" "查询已托管 CLI 的 latest stable Release"
    ui_action S "按来源浏览" "action" "区分发行版、官方仓库、Release、Git 与安装器"
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
    input="$(read_input "搜索 / ID / A / I / U / O / S / R；输入 0 返回" "0")"
    case "$input" in
      0) return 0 ;;
      A|a|all) query=""; catalog_categories_view ;;
      I|i|installed) catalog_installed_view ;;
      U|u) catalog_updates_view ;;
      O|o) catalog_official_updates_view; pause ;;
      S|s|source|sources) catalog_sources_view ;;
      R|r) catalog_refresh_index || true; pause ;;
      "") ;;
      *)
        if catalog_record "$input" >/dev/null 2>&1; then catalog_item_menu "$input"; else query="$input"; fi
        ;;
    esac
  done
}
