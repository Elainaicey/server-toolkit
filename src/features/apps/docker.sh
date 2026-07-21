#!/usr/bin/env bash

docker_require() { command_exists docker || { warn "Docker 未安装，可在软件管理中搜索 docker。"; return 1; }; }

docker_overview() {
  docker_require || return 1
  ui_page "Docker 概览" "Engine、运行中容器和磁盘占用"
  docker version --format 'Engine: {{.Server.Version}}' 2>/dev/null || docker --version
  printf '\n容器：\n'; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
  printf '\n磁盘占用：\n'; docker system df 2>/dev/null || true
}

docker_containers() {
  docker_require || return 1
  ui_page "全部容器" "名称、镜像、状态和端口映射"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

docker_images() {
  docker_require || return 1
  ui_page "Docker 镜像" "仓库、标签、镜像 ID、大小和创建时间"
  docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}'
}

docker_resources() {
  docker_require || return 1
  ui_page "容器资源" "单次采样 CPU、内存、网络和块设备 IO"
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}' 2>/dev/null || warn "无法读取容器资源。"
}

docker_health() {
  docker_require || return 1
  ui_page "Docker 健康检查" "Daemon、容器运行状态、健康检查与异常退出"
  if ! docker info >/dev/null 2>&1; then
    ui_check fail "无法连接 Docker Daemon"
    ui_note "请检查 docker.service 状态或当前用户的 Docker Socket 权限。"
    return 1
  fi
  local total running unhealthy restarting exited
  total="$(docker ps -aq 2>/dev/null | grep -c . || true)"
  running="$(docker ps -q 2>/dev/null | grep -c . || true)"
  unhealthy="$(docker ps -aq --filter health=unhealthy 2>/dev/null | grep -c . || true)"
  restarting="$(docker ps -aq --filter status=restarting 2>/dev/null | grep -c . || true)"
  exited="$(docker ps -aq --filter status=exited 2>/dev/null | grep -c . || true)"
  ui_stats "容器" "$total" "运行" "$running" "异常" "$((unhealthy + restarting))"
  ui_check pass "Docker Daemon 可用"
  if (( unhealthy > 0 )); then ui_check fail "$unhealthy 个容器健康检查失败"; else ui_check pass "没有 unhealthy 容器"; fi
  if (( restarting > 0 )); then ui_check warn "$restarting 个容器正在反复重启"; else ui_check pass "没有反复重启的容器"; fi
  if (( exited > 0 )); then ui_check warn "$exited 个容器处于退出状态"; else ui_check pass "没有已退出容器"; fi
  if (( unhealthy + restarting + exited > 0 )); then
    ui_section "需要关注的容器" "accent"
    printf '  %-24s %-30s %s\n' "名称" "镜像" "状态"
    {
      docker ps -a --filter health=unhealthy --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null
      docker ps -a --filter status=restarting --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null
      docker ps -a --filter status=exited --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null
    } | sort -u | awk -F '|' '{printf "  %-24s %-30s %s\n",$1,$2,$3}'
  fi
}

docker_storage() {
  docker_require || return 1
  ui_page "Docker 存储与网络" "存储卷、虚拟网络与磁盘占用"
  ui_section "存储卷"
  docker volume ls
  ui_section "网络"
  docker network ls
  ui_section "磁盘占用"
  docker system df
}

docker_compose_projects() {
  docker_require || return 1
  ui_page "Compose 项目" "Docker Compose 项目与运行状态"
  if docker compose version >/dev/null 2>&1; then
    docker compose ls --all
  else
    ui_empty "未安装 Docker Compose 插件"
  fi
}

docker_cleanup() {
  docker_require || return 1
  ui_page "Docker 安全清理" "清理未使用对象，但始终保留存储卷"
  docker system df 2>/dev/null || true
  ui_note "只清理已停止容器、未使用网络、悬空镜像和构建缓存；不会删除存储卷。"
  confirm "执行 docker system prune？" || return 0
  require_root
  run docker system prune -f
  audit "action=docker-prune volumes=false"
}

docker_container_action() {
  docker_require || return 1
  local container action state health restart_policy image created pid
  container="$(read_input "容器名称或 ID" "")"; [[ -n "$container" ]] || return 0
  docker inspect "$container" >/dev/null 2>&1 || { warn "没有找到容器：$container"; return 1; }
  while true; do
    docker inspect "$container" >/dev/null 2>&1 || { warn "容器已不存在：$container"; return 0; }
    state="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || printf 'unknown')"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}未配置{{end}}' "$container" 2>/dev/null || printf '未知')"
    restart_policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$container" 2>/dev/null || true)"
    image="$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)"
    created="$(docker inspect --format '{{.Created}}' "$container" 2>/dev/null | cut -d. -f1 || true)"
    pid="$(docker inspect --format '{{.State.Pid}}' "$container" 2>/dev/null || printf '0')"
    ui_page "容器 / $container" "状态、端口、挂载、日志与生命周期"
    ui_panel_begin "容器信息"
    if [[ "$state" == "running" ]]; then ui_panel_kv "状态" "● $state" "$GREEN"; else ui_panel_kv "状态" "● $state" "$YELLOW"; fi
    ui_panel_kv "健康检查" "$health"
    ui_panel_kv "镜像" "${image:-未知}"
    ui_panel_kv "重启策略" "${restart_policy:-no}"
    ui_panel_kv "进程 PID" "$pid"
    ui_panel_kv "创建时间" "${created:-未知}"
    ui_panel_end
    ui_section "端口与挂载" "primary"
    docker port "$container" 2>/dev/null || ui_empty "没有发布端口"
    docker inspect --format '{{range .Mounts}}{{.Type}}: {{.Source}} → {{.Destination}}{{println}}{{end}}' "$container" 2>/dev/null | sed '/^$/d' || true
    ui_section "查看" "primary"
    ui_action 1 "查看日志" "action" "最近 150 条"
    ui_action 2 "资源快照" "action" "CPU、内存、网络和 IO"
    ui_action 3 "完整检查信息" "action" "输出 docker inspect JSON"
    ui_section "生命周期" "accent"
    ui_action 4 "启动" "success"
    ui_action 5 "停止" "danger"
    ui_action 6 "重启" "warning"
    if [[ "$state" == "paused" ]]; then
      ui_action 7 "恢复运行" "success"
    else
      ui_action 7 "暂停" "warning"
    fi
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) docker logs --tail 150 "$container" 2>&1; pause ;;
      2) docker stats --no-stream "$container"; pause ;;
      3) docker inspect "$container"; pause ;;
      4|5|6|7)
        local verb
        case "$action" in
          4) verb=start ;;
          5) verb=stop ;;
          6) verb=restart ;;
          7) if [[ "$state" == "paused" ]]; then verb=unpause; else verb=pause; fi ;;
        esac
        confirm "对容器 $container 执行 $verb？" || continue
        require_root
        run docker "$verb" "$container"
        audit "action=docker-$verb container=$container"
        pause
        ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

docker_menu() {
  local choice
  while true; do
    ui_page "应用与容器 / Docker" "容器生命周期、资源、Compose、网络与存储"
    if command_exists docker; then ui_kv "服务" "$(service_state docker.service)"; else ui_empty "Docker 未安装"; fi
    ui_context "发布容器端口可能绕过 UFW；公网服务请同时检查 Docker 防火墙规则。"
    ui_section "观察" "primary"
    ui_item 1 "Docker 概览"
    ui_item 2 "Docker 健康检查" "异常退出、重启循环与容器健康状态"
    ui_item 3 "全部容器"
    ui_item 4 "镜像"
    ui_item 5 "容器资源"
    ui_item 6 "存储卷与网络"
    ui_item 7 "Compose 项目"
    ui_section "操作" "accent"
    ui_item 8 "管理一个容器" "详情、日志、资源与生命周期"
    ui_item 9 "安全清理"
    ui_item 10 "安装 Docker"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) docker_overview || true ;;
      2) docker_health || true ;;
      3) docker_containers || true ;;
      4) docker_images || true ;;
      5) docker_resources || true ;;
      6) docker_storage || true ;;
      7) docker_compose_projects || true ;;
      8) docker_container_action || true ;;
      9) docker_cleanup || true ;;
      10) catalog_install docker || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
