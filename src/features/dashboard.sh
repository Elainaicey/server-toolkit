#!/usr/bin/env bash

dashboard_show() {
  platform_detect
  local failed_units running_services listeners upgrades docker_state="未安装" containers="-"
  failed_units="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
  running_services="$(systemctl --type=service --state=running --no-legend 2>/dev/null | grep -c . || true)"
  listeners="0"
  if command_exists ss; then
    listeners="$(ss -H -ltn 2>/dev/null | wc -l | tr -d ' ' || true)"
  fi
  upgrades="$(package_upgradable_count)"
  if command_exists docker; then
    docker_state="$(service_state docker.service)"
    containers="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ' || true) running"
  fi

  ui_header "系统仪表盘"
  ui_section "主机"
  ui_kv "系统" "$OS_NAME"
  ui_kv "环境" "$ARCH · $VIRTUALIZATION"
  ui_kv "运行时间" "$UPTIME_TEXT"
  ui_kv "负载" "$LOAD_AVERAGE"
  ui_kv "资源" "$CPU_CORES CPU · $MEMORY_MB MB RAM · $SWAP_MB MB Swap"
  ui_kv "根分区" "${ROOT_USAGE:-未知}"

  ui_section "运行状态"
  ui_kv "服务" "$running_services running · $failed_units failed"
  ui_kv "TCP 监听" "$listeners"
  ui_kv "可更新软件" "$upgrades"
  ui_kv "Docker" "$docker_state · $containers"

  if (( failed_units > 0 )); then warn "存在失败的 systemd 服务，请进入服务与日志。"; fi
  if [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB < 512 )) && [[ "$SWAP_MB" == "0" ]]; then
    warn "内存较小且没有 Swap。"
  fi
}
