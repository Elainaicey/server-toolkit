#!/usr/bin/env bash
# 测试桩由应用 reload 流程间接调用。
# shellcheck disable=SC2034,SC2317,SC2329
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/features/apps.sh"

[[ "$(apps_service_record 1)" == 'docker|Docker|docker.service|docker|docker-ce|容器引擎' ]] || {
  printf 'FAIL: Docker 应用服务映射错误\n' >&2
  exit 1
}
[[ "$(apps_service_record 9)" == 'x-ui|3x-ui|x-ui.service|||代理面板' ]] || {
  printf 'FAIL: 3x-ui 应用服务映射错误\n' >&2
  exit 1
}
[[ "$(apps_service_catalog | awk -F '|' '{print $3}' | sort -u | wc -l | tr -d ' ')" == "9" ]] || {
  printf 'FAIL: 应用服务名称不唯一\n' >&2
  exit 1
}
[[ "$(apps_service_unit nginx)" == "nginx.service" &&
  "$(apps_service_catalog_id nginx)" == "nginx" &&
  "$(apps_service_package nginx)" == "nginx" &&
  "$(apps_service_field nginx 6)" == "Web 服务" ]] || {
  printf 'FAIL: 应用服务字段读取错误\n' >&2
  exit 1
}
apps_service_config_validation_supported nginx || {
  printf 'FAIL: Nginx 没有声明配置检查能力\n' >&2
  exit 1
}
apps_service_reload_supported caddy || {
  printf 'FAIL: Caddy 没有声明安全 reload 能力\n' >&2
  exit 1
}
if apps_service_reload_supported redis; then
  printf 'FAIL: Redis 被错误声明为通用安全 reload\n' >&2
  exit 1
fi
grep -Fxq /etc/nginx/nginx.conf < <(apps_service_config_paths nginx) || {
  printf 'FAIL: Nginx 配置资产缺少主配置\n' >&2
  exit 1
}

valid_service_name() { return 0; }
terminal_safe_text() { printf '%s' "$1"; }
systemctl() {
  if [[ "$1" == "show" && "$4" == "ControlGroup" ]]; then
    return 0
  elif [[ "$1" == "show" && "$4" == "MainPID" ]]; then
    printf '123\n'
  fi
}
command_exists() { [[ "$1" == "ss" ]]; }
ss() {
  printf '%s\n' \
    'tcp LISTEN 0 511 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=123,fd=6))' \
    'tcp LISTEN 0 4096 127.0.0.1:5432 0.0.0.0:* users:(("postgres",pid=456,fd=7))'
}
listeners="$(apps_service_listener_rows nginx.service)"
[[ "$(grep -c . <<<"$listeners")" -eq 1 && "$listeners" == *"0.0.0.0:80"* ]] || {
  printf 'FAIL: 应用监听端口没有按 systemd PID 过滤\n' >&2
  exit 1
}

DRY_RUN=1
captured=""
service_state() { printf 'active'; }
systemctl() {
  if [[ "$1" == "show" && "$4" == "CanReload" ]]; then
    printf 'yes\n'
  elif [[ "$1" == "show" && "$4" == "ExecReload" ]]; then
    printf '{ path=/usr/sbin/nginx ; argv[]=/usr/sbin/nginx -s reload ; }\n'
  fi
}
apps_service_config_validate() { return 0; }
confirm() { return 0; }
require_root() { :; }
run() { captured="$1 $2 $3"; }
audit() { :; }
ui_page() { :; }
ui_success() { :; }
warn() { :; }

apps_service_reload nginx >/dev/null
[[ "$captured" == "systemctl reload nginx.service" ]] || {
  printf 'FAIL: Nginx 安全 reload 没有调用声明的 systemd 服务\n' >&2
  exit 1
}
captured=""
apps_service_config_validate() { return 1; }
if apps_service_reload nginx >/dev/null 2>&1; then
  printf 'FAIL: 配置检查失败后仍允许应用 reload\n' >&2
  exit 1
fi
[[ -z "$captured" ]] || {
  printf 'FAIL: 配置检查失败后仍执行了 systemctl\n' >&2
  exit 1
}

printf 'PASS: apps\n'
