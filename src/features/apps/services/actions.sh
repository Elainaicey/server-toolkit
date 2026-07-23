#!/usr/bin/env bash

apps_service_config_validate() {
  local app_id="$1" label config
  label="$(apps_service_label "$app_id")"
  ui_page "$label / 配置检查" "调用应用官方只读检查命令，不重新加载服务"
  case "$app_id" in
    nginx)
      command_exists nginx || { warn "没有找到 nginx 命令。"; return 1; }
      nginx -t || { warn "Nginx 配置检查失败。"; return 1; }
      ;;
    caddy)
      command_exists caddy || { warn "没有找到 caddy 命令。"; return 1; }
      config=/etc/caddy/Caddyfile
      [[ -f "$config" ]] || { warn "没有找到 Caddyfile：$config"; return 1; }
      caddy validate --config "$config" || { warn "Caddy 配置检查失败。"; return 1; }
      ;;
    apache)
      command_exists apache2ctl || { warn "没有找到 apache2ctl 命令。"; return 1; }
      apache2ctl configtest || { warn "Apache 配置检查失败。"; return 1; }
      ;;
    docker)
      command_exists dockerd || { warn "没有找到 dockerd 命令。"; return 1; }
      config=/etc/docker/daemon.json
      [[ -f "$config" ]] || { ui_note "没有 daemon.json；Docker 使用内置默认配置。"; return 0; }
      dockerd --validate --config-file "$config" || { warn "Docker daemon.json 检查失败。"; return 1; }
      ;;
    *)
      warn "$label 当前没有安全、无副作用的官方配置检查命令。"
      return 1
      ;;
  esac
  ui_success "$label 配置检查通过"
}

apps_service_runtime_check() {
  local app_id="$1" output
  case "$app_id" in
    docker)
      command_exists docker && docker info >/dev/null 2>&1
      ;;
    nginx)
      command_exists nginx && nginx -t >/dev/null 2>&1
      ;;
    caddy)
      command_exists caddy && [[ -f /etc/caddy/Caddyfile ]] &&
        caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1
      ;;
    apache)
      command_exists apache2ctl && apache2ctl configtest >/dev/null 2>&1
      ;;
    redis)
      command_exists redis-cli || return 2
      if command_exists timeout; then
        output="$(timeout 4 redis-cli -h 127.0.0.1 ping 2>/dev/null || true)"
      else
        output="$(redis-cli -h 127.0.0.1 ping 2>/dev/null || true)"
      fi
      [[ "$output" == "PONG" || "$output" == *"NOAUTH"* ]]
      ;;
    postgresql)
      command_exists pg_isready || return 2
      pg_isready -q -t 3
      ;;
    *) return 2 ;;
  esac
}

apps_service_health() {
  local app_id="$1" label service state enabled listeners recent_errors runtime_status
  label="$(apps_service_label "$app_id")"
  service="$(apps_service_unit "$app_id")"
  state="$(service_state "$service")"
  enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
  enabled="${enabled:-disabled}"
  listeners="$(apps_service_listener_count "$service")"
  recent_errors="$(journalctl -u "$service" --since "-1 hour" -p err --no-pager 2>/dev/null | grep -c . || true)"
  ui_page "$label / 运行健康" "systemd、应用响应、监听端口与最近错误"
  if [[ "$state" == "active" ]]; then
    ui_check pass "systemd 服务处于 active"
  else
    ui_check fail "systemd 服务状态为 $state"
  fi
  if apps_service_runtime_check "$app_id"; then
    runtime_status=0
    ui_check pass "应用级只读检查通过"
  else
    runtime_status=$?
    if [[ "$runtime_status" -eq 2 ]]; then
      ui_check warn "该应用没有可安全执行的无认证运行检查"
    else
      ui_check fail "应用级只读检查失败"
    fi
  fi
  if [[ "$listeners" =~ ^[0-9]+$ ]] && (( listeners > 0 )); then
    ui_check pass "关联到 $listeners 个监听套接字"
  else
    ui_check warn "没有通过 systemd cgroup 关联到监听套接字"
  fi
  if [[ "$recent_errors" =~ ^[0-9]+$ ]] && (( recent_errors > 0 )); then
    ui_check warn "最近 1 小时有 $recent_errors 条 err 级日志"
  else
    ui_check pass "最近 1 小时没有 err 级日志"
  fi
  ui_kv "开机启动" "$enabled"
  ui_note "检查仅在打开页面时运行一次，不会创建定时任务或后台监控。"
}

apps_service_reload() {
  local app_id="$1" label service state can_reload exec_reload
  apps_service_reload_supported "$app_id" || { warn "该应用未声明安全 reload 流程。"; return 1; }
  label="$(apps_service_label "$app_id")"
  service="$(apps_service_unit "$app_id")"
  state="$(service_state "$service")"
  [[ "$state" == "active" ]] || { warn "$label 当前未运行，不能 reload。"; return 1; }
  can_reload="$(systemctl show "$service" -p CanReload --value 2>/dev/null || true)"
  exec_reload="$(systemctl show "$service" -p ExecReload --value 2>/dev/null || true)"
  if [[ "$can_reload" != "yes" && -z "$exec_reload" ]]; then
    warn "$service 没有声明 systemd reload 能力。"
    return 1
  fi
  apps_service_config_validate "$app_id" || {
    warn "配置检查失败，已阻止 reload。"
    return 1
  }
  ui_page "$label / 安全重新加载" "配置已通过检查；reload 不主动终止现有服务进程"
  confirm "重新加载 $label 配置？" || return 0
  require_root
  run systemctl reload "$service" || { warn "$label reload 失败。"; return 1; }
  if [[ "$DRY_RUN" -eq 0 ]]; then
    systemctl is-active --quiet "$service" || { warn "reload 后 $label 未保持运行。"; return 1; }
  fi
  audit "action=app-reload app=$app_id service=$service"
  ui_success "$label 配置已重新加载"
}
