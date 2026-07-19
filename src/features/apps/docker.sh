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
  local container action
  container="$(read_input "容器名称或 ID" "")"; [[ -n "$container" ]] || return 0
  docker inspect "$container" >/dev/null 2>&1 || { warn "没有找到容器：$container"; return 1; }
  ui_page "容器 / $container" "日志、检查与生命周期操作"
  ui_section "查看" "primary"
  ui_action 1 "查看日志" "action"
  ui_action 2 "检查详情" "action"
  ui_section "生命周期" "accent"
  ui_action 3 "启动" "success"
  ui_action 4 "停止" "danger"
  ui_action 5 "重启" "warning"
  ui_action 0 "返回" "muted"
  action="$(read_input "请选择" "0")"
  case "$action" in
    1) docker logs --tail 150 "$container" 2>&1 ;;
    2) docker inspect "$container" ;;
    3|4|5)
      local verb
      case "$action" in
        3) verb=start ;;
        4) verb=stop ;;
        5) verb=restart ;;
      esac
      confirm "对容器 $container 执行 $verb？" || return 0; require_root; run docker "$verb" "$container"; audit "action=docker-$verb container=$container"
      ;;
    0) return 0 ;;
    *) warn "未知选项" ;;
  esac
}

docker_menu() {
  local choice
  while true; do
    ui_page "应用与容器 / Docker" "容器生命周期、资源、Compose、网络与存储"
    if command_exists docker; then ui_kv "服务" "$(service_state docker.service)"; else ui_empty "Docker 未安装"; fi
    ui_context "发布容器端口可能绕过 UFW；公网服务请同时检查 Docker 防火墙规则。"
    ui_section "观察" "primary"
    ui_item 1 "Docker 概览"
    ui_item 2 "全部容器"
    ui_item 3 "镜像"
    ui_item 4 "容器资源"
    ui_item 5 "存储卷与网络"
    ui_item 6 "Compose 项目"
    ui_section "操作" "accent"
    ui_item 7 "操作一个容器"
    ui_item 8 "安全清理"
    ui_item 9 "安装 Docker"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) docker_overview || true ;;
      2) docker_containers || true ;;
      3) docker_images || true ;;
      4) docker_resources || true ;;
      5) docker_storage || true ;;
      6) docker_compose_projects || true ;;
      7) docker_container_action || true ;;
      8) docker_cleanup || true ;;
      9) catalog_install docker || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
