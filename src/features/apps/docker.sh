#!/usr/bin/env bash

docker_require() { command_exists docker || { warn "Docker 未安装，可在软件管理中搜索 docker。"; return 1; }; }

docker_overview() {
  docker_require || return 1
  ui_header "Docker 概览"
  docker version --format 'Engine: {{.Server.Version}}' 2>/dev/null || docker --version
  printf '\n容器：\n'; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
  printf '\n磁盘占用：\n'; docker system df 2>/dev/null || true
}

docker_containers() {
  docker_require || return 1
  ui_header "全部容器"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

docker_images() {
  docker_require || return 1
  ui_header "镜像"
  docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}'
}

docker_resources() {
  docker_require || return 1
  ui_header "容器资源"
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}' 2>/dev/null || warn "无法读取容器资源。"
}

docker_storage() {
  docker_require || return 1
  ui_header "Docker 存储与网络"
  ui_section "存储卷"
  docker volume ls
  ui_section "网络"
  docker network ls
  ui_section "磁盘占用"
  docker system df
}

docker_compose_projects() {
  docker_require || return 1
  ui_header "Compose 项目"
  if docker compose version >/dev/null 2>&1; then
    docker compose ls --all
  else
    ui_empty "未安装 Docker Compose 插件"
  fi
}

docker_cleanup() {
  docker_require || return 1
  ui_header "Docker 安全清理"
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
  ui_header "容器 $container"
  ui_item 1 "查看日志"
  ui_item 2 "检查详情"
  ui_item 3 "启动"
  ui_item 4 "停止"
  ui_item 5 "重启"
  ui_item 0 "返回"
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
    ui_clear
    ui_header "Docker"
    if command_exists docker; then ui_kv "服务" "$(service_state docker.service)"; else ui_empty "Docker 未安装"; fi
    printf '%b发布容器端口可能绕过 UFW；公网服务请同时检查 Docker 防火墙规则。%b\n\n' "$DIM" "$NC"
    ui_item 1 "Docker 概览"
    ui_item 2 "全部容器"
    ui_item 3 "镜像"
    ui_item 4 "容器资源"
    ui_item 5 "存储卷与网络"
    ui_item 6 "Compose 项目"
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
