#!/usr/bin/env bash

catalog_switch_source() {
  local id="$1" record _id category name description packages handler current candidate
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  [[ "$handler" == "official_release" ]] || { warn "$name 不提供可切换的安装来源。"; return 1; }
  if software_release_managed "$id"; then
    [[ -n "$packages" ]] || { warn "$name 仅提供项目官方 Release，没有发行版软件包可切换。"; return 1; }
    candidate="$(package_candidate_version "$packages")"
    [[ -n "$candidate" && "$candidate" != "(none)" ]] || { warn "当前软件源不提供 $packages。"; return 1; }
    ui_page "切换软件来源 / $name" "$id · 官方 Release → 发行版仓库"
    ui_panel_begin "切换计划"
    ui_panel_kv "当前来源" "项目官方 GitHub Release" "$CYAN"
    ui_panel_kv "目标来源" "Debian / Ubuntu 软件仓库" "$YELLOW"
    ui_panel_kv "目标版本" "$candidate"
    ui_panel_kv "系统包" "$packages"
    ui_panel_end
    ui_note "先安装发行版候选版本，再删除由 Server Toolkit 管理的 /usr/local/bin 命令。"
    confirm "切换到发行版软件仓库？" || return 0
    require_root
    package_install_latest "$packages" || return 1
    software_remove_release "$id" || return 1
    current="official-release"
  else
    ui_page "切换软件来源 / $name" "$id · 发行版仓库 → 官方 Release"
    ui_panel_begin "切换计划"
    ui_panel_kv "当前来源" "Debian / Ubuntu 软件仓库" "$CYAN"
    ui_panel_kv "目标来源" "项目官方 GitHub Release" "$GREEN"
    ui_panel_kv "发布通道" "latest stable"
    ui_panel_kv "命令路径" "$(software_release_target "$id")"
    ui_panel_kv "完整性" "GitHub SHA-256 digest"
    ui_panel_end
    ui_note "系统包会保留；官方命令安装到 /usr/local/bin 并优先于 /usr/bin，可随时切回。"
    confirm "切换到项目官方稳定版？" || return 0
    require_root
    software_install_release "$id" || return 1
    current="distribution"
  fi
  audit "action=software-source-switch id=$id from=$current"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "$name 来源切换预览完成。"
  else
    ui_success "$name 已切换到 $(catalog_source_label "$record")。"
  fi
}

catalog_install() {
  local id="$1" record _id category name description packages handler source_label provider selected_handler choice candidate
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  if catalog_installed "$record"; then
    if [[ "$handler" == "official_release" ]] && ! software_release_managed "$id"; then
      catalog_switch_source "$id"
      return
    fi
    if provider="$(catalog_prompt_provider "$handler" 2>/dev/null)"; then
      software_prompt_active "$provider" && { info "$name 已经安装并处于启用状态。"; return 0; }
      ui_page "启用提示符 / $name" "$id · $category"
      ui_note "该操作只切换 Server Toolkit 托管的活动提示符，不卸载其他引擎。"
      confirm "将 $name 设为当前 Zsh 提示符？" || return 0
      require_root
      software_activate_prompt "$provider" || { warn "$name 启用失败。"; return 1; }
      audit "action=prompt-activate id=$id"
      ui_success "$name 已启用；重新进入 Zsh 后生效。"
      return 0
    fi
    info "$name 已经安装。"
    return 0
  fi
  catalog_available "$record" || { warn "当前平台没有可用的 $name 安装来源。"; return 1; }
  selected_handler="$handler"
  if [[ "$handler" == "official_release" && -n "$packages" ]]; then
    candidate="$(package_candidate_version "$packages")"
    if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
      ui_page "选择软件来源 / $name" "$id · 可在安装后随时切换"
      ui_action 1 "项目官方稳定版" "success" "GitHub Release · SHA-256 校验 · 推荐"
      ui_action 2 "发行版稳定版" "action" "$packages · $candidate · 系统兼容优先"
      ui_action 0 "取消" "muted"
      choice="$(read_input "请选择来源" "1")"
      case "$choice" in
        1) selected_handler="official_release" ;;
        2) selected_handler="" ;;
        0) return 0 ;;
        *) warn "未知来源选项：$choice"; return 1 ;;
      esac
    fi
  fi
  ui_page "安装软件 / $name" "$id · $category"
  ui_panel_begin "变更摘要"
  ui_panel_kv "软件" "$name" "$CYAN"
  ui_panel_kv "说明" "$description"
  source_label="$(catalog_source_label "$record")"
  [[ -n "$selected_handler" ]] || source_label="Debian / Ubuntu 软件仓库"
  ui_panel_kv "来源" "$source_label"
  if [[ "$selected_handler" == "official_release" ]]; then
    ui_panel_kv "目标版本" "官方最新稳定版（安装时查询）" "$GREEN"
    ui_panel_kv "官方项目" "$(software_release_repository "$id")"
    ui_panel_kv "命令路径" "$(software_release_target "$id")"
    ui_panel_kv "完整性" "GitHub Release SHA-256 digest"
  else
    if [[ -z "$selected_handler" ]]; then
      candidate="$(package_candidate_version "$packages")"
    else
      candidate="$(catalog_candidate_version "$record")"
    fi
    ui_panel_kv "目标版本" "${candidate:-—}" "$GREEN"
  fi
  if [[ "$selected_handler" == "oh_my_zsh" ]]; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "目标目录" "$(software_oh_my_zsh_path)"
    ui_panel_kv "必要依赖" "zsh + git"
  elif catalog_prompt_provider "$selected_handler" >/dev/null 2>&1; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "配置文件" "$(software_target_home "$(software_target_user)")/.zshrc"
    ui_panel_kv "提示" "安装后会切换为当前提示符；其他已安装提示符保留"
  elif [[ -n "$packages" && "$selected_handler" != "official_release" ]]; then
    ui_panel_kv "系统包" "$packages"
  fi
  ui_panel_end
  confirm "确认安装 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$selected_handler" in
    docker_official) software_install_docker || return 1 ;;
    caddy_official) software_install_caddy || return 1 ;;
    oh_my_zsh) software_install_oh_my_zsh || return 1 ;;
    starship_prompt) software_install_starship || return 1 ;;
    oh_my_posh_prompt) software_install_oh_my_posh || return 1 ;;
    spaceship_prompt) software_install_spaceship || return 1 ;;
    official_release) software_install_release "$id" || return 1 ;;
    "") package_install_latest "$packages" || return 1 ;;
    *) die "未知安装器：$selected_handler" ;;
  esac
  audit "action=software-install id=$id source=$(printf '%q' "$source_label")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "$name 安装预览完成。"
  else
    catalog_installed "$record" || { warn "$name 安装后未通过状态验证。"; return 1; }
    ui_success "$name 已安装：$(catalog_installed_version "$record")"
  fi
}

catalog_update() {
  local id="$1" record _id category name description packages handler installed candidate provider latest
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" || { warn "$name 尚未安装，请先执行安装。"; return 1; }
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  if [[ "$handler" == "official_release" ]] && software_release_managed "$id"; then
    ui_page "检查官方更新 / $name" "$id · 项目官方 GitHub Release"
    ui_panel_begin "官方稳定通道"
    ui_panel_kv "当前版本" "$installed" "$WHITE"
    ui_panel_kv "官方项目" "$(software_release_repository "$id")"
    ui_panel_kv "完整性" "$(software_release_integrity "$id" && printf 'SHA-256 正常' || printf '异常')" \
      "$(software_release_integrity "$id" && printf '%s' "$GREEN" || printf '%s' "$RED")"
    ui_panel_kv "检查方式" "GitHub latest stable Release"
    ui_panel_end
    confirm "查询官方版本并按需更新 $name？" || return 0
    require_root
    software_release_load_latest "$id" || return 1
    latest="$SOFTWARE_RELEASE_LATEST_VERSION"
    software_update_release "$id" || return 1
    audit "action=software-update id=$id source=official-release from=$installed to=$latest"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "$name 官方更新预览完成。"
    elif [[ "$installed" == "$(software_release_version "$id")" ]]; then
      ui_success "$name 已经是官方最新稳定版 $installed。"
    else
      ui_success "$name 已更新：$installed → $(software_release_version "$id")"
    fi
    return 0
  elif [[ "$handler" == "official_release" ]]; then
    handler=""
    candidate="$(package_candidate_version "$packages")"
  fi
  if provider="$(catalog_prompt_provider "$handler" 2>/dev/null)"; then
    ui_page "更新提示符 / $name" "$id · $category"
    ui_panel_begin "官方更新"
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "当前版本" "$installed" "$WHITE"
    ui_panel_kv "更新来源" "$candidate" "$YELLOW"
    ui_panel_end
    confirm "检查并更新 $name？" || return 0
    require_root
    software_update_prompt "$provider" || { warn "$name 更新失败。"; return 1; }
    if [[ "$DRY_RUN" -eq 0 ]]; then
      catalog_installed "$record" || { warn "$name 更新后未通过状态验证。"; return 1; }
    fi
    audit "action=software-update id=$id from=$installed"
    ui_success "$name 已检查官方更新：$(catalog_installed_version "$record")"
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
    software_update_oh_my_zsh || { warn "$name 更新失败。"; return 1; }
    if [[ "$DRY_RUN" -eq 0 ]]; then
      catalog_installed "$record" || { warn "$name 更新后未通过状态验证。"; return 1; }
    fi
    audit "action=software-update id=$id from=$installed"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "$name 更新预览完成。"
    else
      ui_success "$name 已检查官方更新：$(catalog_installed_version "$record")"
    fi
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
  package_update_index || return 1
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
    docker_official) software_update_docker || return 1 ;;
    caddy_official) software_update_caddy || return 1 ;;
    oh_my_zsh) software_update_oh_my_zsh || return 1 ;;
    starship_prompt) software_update_prompt starship || return 1 ;;
    oh_my_posh_prompt) software_update_prompt oh-my-posh || return 1 ;;
    spaceship_prompt) software_update_prompt spaceship || return 1 ;;
    "") package_upgrade "$packages" || return 1 ;;
    *) die "未知安装器：$handler" ;;
  esac
  if [[ "$DRY_RUN" -eq 0 ]]; then
    catalog_installed "$record" || { warn "$name 更新后未通过状态验证。"; return 1; }
  fi
  audit "action=software-update id=$id from=$installed to=$candidate"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "$name 更新预览完成。"
  else
    ui_success "$name 已更新：$(catalog_installed_version "$record")"
  fi
}

catalog_remove() {
  local id="$1" record _id category name description packages handler release_managed=0
  record="$(catalog_record "$id")" || { warn "软件目录中没有 '$id'。"; return 1; }
  IFS='|' read -r _id category name description packages handler <<<"$record"
  catalog_installed "$record" || { info "$name 未安装。"; return 0; }
  ui_page "移除软件 / $name" "$id · $category"
  ui_panel_begin "变更摘要"
  ui_panel_kv "软件" "$name" "$CYAN"
  ui_panel_kv "当前版本" "$(catalog_installed_version "$record")"
  if [[ "$handler" == "official_release" ]]; then
    software_release_managed "$id" && release_managed=1
    ui_panel_kv "当前来源" "$(catalog_source_label "$record")" "$CYAN"
    if (( release_managed == 1 )); then
      ui_panel_kv "托管命令" "$(software_release_target "$id")"
      ui_panel_kv "完整性" "$(software_release_integrity "$id" && printf '正常' || printf '异常')"
    fi
    [[ -z "$packages" ]] || ui_panel_kv "底层系统包" "$packages"
  elif [[ "$handler" == "oh_my_zsh" ]]; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "目标目录" "$(software_oh_my_zsh_path)"
  elif catalog_prompt_provider "$handler" >/dev/null 2>&1; then
    ui_panel_kv "安装用户" "$(software_target_user)" "$CYAN"
    ui_panel_kv "配置文件" "$(software_target_home "$(software_target_user)")/.zshrc"
  else
    ui_panel_kv "系统包" "${packages:-由官方安装器管理}"
  fi
  ui_panel_end
  if [[ "$handler" == "official_release" ]]; then
    ui_danger "将移除 Server Toolkit 托管的官方命令；如同时安装了对应系统包，也会一并移除。"
  elif [[ "$handler" == "oh_my_zsh" ]]; then
    ui_danger "将移除官方框架目录和 Server Toolkit 托管的 .zshrc 配置块；保留其他用户配置、Zsh、Git 与默认 Shell。"
  elif catalog_prompt_provider "$handler" >/dev/null 2>&1; then
    ui_danger "只移除当前提示符的托管文件和活动配置块；其他提示符与用户配置保持不变。"
  else
    ui_danger "只移除软件包，不删除它的数据目录和配置文件。"
  fi
  confirm "确认移除 $name？" || { warn "已取消。"; return 0; }
  require_root
  case "$handler" in
    docker_official) software_remove_docker || return 1 ;;
    caddy_official) software_remove_caddy || return 1 ;;
    oh_my_zsh) software_remove_oh_my_zsh || return 1 ;;
    starship_prompt) software_remove_prompt starship || return 1 ;;
    oh_my_posh_prompt) software_remove_prompt oh-my-posh || return 1 ;;
    spaceship_prompt) software_remove_prompt spaceship || return 1 ;;
    official_release)
      if (( release_managed == 1 )); then software_remove_release "$id" || return 1; fi
      if [[ -n "$packages" ]]; then package_remove "$packages" || return 1; fi
      ;;
    "") package_remove "$packages" || return 1 ;;
    *) die "未知安装器：$handler" ;;
  esac
  if [[ "$DRY_RUN" -eq 0 ]] && catalog_installed "$record"; then
    warn "$name 移除后仍能被检测到；为避免误报，操作未标记为成功。"
    return 1
  fi
  audit "action=software-remove id=$id"
  ui_success "$name 移除完成。"
}
