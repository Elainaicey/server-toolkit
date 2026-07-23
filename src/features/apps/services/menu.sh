#!/usr/bin/env bash

apps_service_summary() {
  local app_id label service _catalog_id _package_name category state enabled style
  local count=0 running=0 installed=0 version
  ui_page "应用服务管理" "应用版本、健康、端口、配置、数据与 systemd 生命周期"
  while IFS='|' read -r app_id label service _catalog_id _package_name category; do
    count=$((count + 1))
    if service_exists "$service"; then
      installed=$((installed + 1))
      state="$(service_state "$service")"
      enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
      enabled="${enabled:-disabled}"
      version="$(apps_service_version "$app_id")"
      if [[ "$state" == "active" ]]; then
        style="good"
        running=$((running + 1))
      elif [[ "$state" == "failed" ]]; then
        style="danger"
      else
        style="warn"
      fi
      ui_state_item "$count" "$label" "$state" "$style" "$category · $version · 开机 $enabled"
    else
      ui_state_item "$count" "$label" "未安装" "muted" "$category · $service"
    fi
  done < <(apps_service_catalog)
  ui_stats "目录" "$count" "已安装" "$installed" "运行中" "$running"
  ui_note "所有健康和占用检查均为手动触发；应用中心不会创建后台监控。"
  ui_action 0 "返回" "muted"
}

apps_service_detail() {
  local app_id="$1" label service action state enabled version main_pid restarts listeners configs data state_color
  local catalog_id catalog_record_data candidate software_state
  label="$(apps_service_label "$app_id")" || return 1
  service="$(apps_service_unit "$app_id")"
  catalog_id="$(apps_service_catalog_id "$app_id")"
  service_exists "$service" || { warn "没有找到应用服务：$service"; return 1; }
  while true; do
    state="$(service_state "$service")"
    enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
    enabled="${enabled:-disabled}"
    version="$(apps_service_version "$app_id")"
    main_pid="$(systemctl show "$service" -p MainPID --value 2>/dev/null || true)"
    restarts="$(systemctl show "$service" -p NRestarts --value 2>/dev/null || true)"
    listeners="$(apps_service_listener_count "$service")"
    configs="$(apps_service_existing_path_count "$app_id")"
    data="$(apps_service_data_existing_count "$app_id")"
    case "$state" in active) state_color="$GREEN" ;; failed) state_color="$RED" ;; *) state_color="$YELLOW" ;; esac
    ui_page "应用 / $label" "应用资产与通用服务生命周期"
    ui_panel_begin "运行信息"
    ui_panel_kv "状态" "● $state" "$state_color"
    ui_panel_kv "版本" "$version"
    ui_panel_kv "服务" "$service"
    ui_panel_kv "开机启动" "$enabled"
    ui_panel_kv "主进程 PID" "${main_pid:-0}"
    ui_panel_kv "重启次数" "${restarts:-0}"
    if [[ -n "$catalog_id" ]]; then
      catalog_record_data="$(catalog_record "$catalog_id" 2>/dev/null || true)"
      if [[ -n "$catalog_record_data" ]]; then
        candidate="$(catalog_candidate_version "$catalog_record_data")"
        software_state="$(catalog_state "$catalog_record_data" "$candidate")"
        ui_panel_kv "软件候选版本" "$candidate"
        ui_panel_kv "软件更新状态" "$(catalog_state_badge "$software_state")"
      fi
    fi
    ui_panel_end
    ui_stats "监听" "$listeners" "配置路径" "$configs" "数据路径" "$data"
    ui_section "应用观察" "primary"
    ui_action_pair 1 "运行健康" "action" 2 "监听端口" "action"
    ui_action_pair 3 "配置资产" "action" 4 "数据与占用" "warning"
    ui_action 5 "最近日志" "action"
    ui_section "安全操作" "accent"
    if apps_service_config_validation_supported "$app_id"; then
      ui_action 6 "检查配置" "action" "使用应用官方检查命令"
    else
      ui_action 6 "检查配置" "disabled" "没有安全的无副作用检查命令"
    fi
    if apps_service_reload_supported "$app_id"; then
      ui_action 7 "安全 reload" "warning" "先检查配置，再重新加载"
    else
      ui_action 7 "安全 reload" "disabled" "该应用未声明 reload 流程"
    fi
    ui_action 8 "完整 systemd 管理" "action" "资源、依赖、失败诊断与生命周期"
    if [[ -n "$catalog_id" ]]; then
      ui_action 9 "软件版本与更新" "action" "候选版本、来源、更新与安全移除"
    else
      ui_action 9 "软件版本与更新" "disabled" "未声明可验证的软件目录来源"
    fi
    if [[ "$app_id" == "docker" ]]; then ui_action 10 "Docker 专属中心" "action"; fi
    ui_action 0 "返回应用清单" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) apps_service_health "$app_id" ;;
      2) apps_service_listeners_view "$app_id" ;;
      3) apps_service_configuration_view "$app_id" ;;
      4) apps_service_data_view "$app_id" ;;
      5) services_logs "$service" ;;
      6)
        if apps_service_config_validation_supported "$app_id"; then apps_service_config_validate "$app_id" || true
        else warn "该应用没有可用的配置检查。"; fi
        ;;
      7)
        if apps_service_reload_supported "$app_id"; then apps_service_reload "$app_id" || true
        else warn "该应用没有安全 reload 流程。"; fi
        ;;
      8) services_select "$service"; continue ;;
      9)
        if [[ -n "$catalog_id" ]]; then catalog_item_menu "$catalog_id"
        else warn "该应用没有可验证的软件目录来源。"; fi
        continue
        ;;
      10) if [[ "$app_id" == "docker" ]]; then docker_menu; else warn "未知选项"; fi; continue ;;
      0) return 0 ;;
      *) warn "未知选项：$action"; continue ;;
    esac
    pause
  done
}

apps_service_manage() {
  local choice record app_id label service catalog_id _package _category
  while true; do
    apps_service_summary
    choice="$(read_input "请选择应用" "0")"
    [[ "$choice" == "0" ]] && return 0
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "选项无效。"; pause; continue; }
    record="$(apps_service_record "$choice" 2>/dev/null || true)"
    [[ -n "$record" ]] || { warn "未知应用编号：$choice"; pause; continue; }
    IFS='|' read -r app_id label service catalog_id _package _category <<<"$record"
    if service_exists "$service"; then
      apps_service_detail "$app_id"
    elif [[ -n "$catalog_id" ]]; then
      ui_note "$label 尚未安装，将进入单项软件安装流程。"
      catalog_install "$catalog_id" || true
      pause
    else
      warn "$label 未安装，当前只管理已经存在的 $service。"
      pause
    fi
  done
}
