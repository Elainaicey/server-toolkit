#!/usr/bin/env bash
# 功能模块通过运行时解析这些测试桩。
# shellcheck disable=SC2034,SC2317,SC2329
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/validation.sh"
. "$ROOT_DIR/src/features/services.sh"

[[ "$(services_format_cpu_time 60000000000)" == "1.0 分钟" ]] || {
  printf 'FAIL: 服务 CPU 时间格式化错误\n' >&2
  exit 1
}
[[ "$(services_format_bytes invalid)" == "—" ]] || {
  printf 'FAIL: 无效服务内存值没有安全降级\n' >&2
  exit 1
}
[[ "$(services_path_summary '/etc/a.conf /etc/b.conf')" == "2 个 · /etc/a.conf …" ]] || {
  printf 'FAIL: 服务 Drop-in 路径摘要错误\n' >&2
  exit 1
}

DRY_RUN=1
captured=""
confirm() { return 0; }
require_root() { :; }
service_exists() { [[ "$1" == "nginx.service" || "$1" == "apt-daily.service" ]]; }
unit_exists() { service_exists "$1"; }
run() { captured="$1 $2 $3"; }
ui_success() { :; }

services_apply_action nginx.service restart >/dev/null
[[ "$captured" == "systemctl restart nginx.service" ]] || {
  printf 'FAIL: 服务重启没有进入统一操作入口\n' >&2
  exit 1
}
if services_apply_action nginx.service reload >/dev/null 2>&1; then
  printf 'FAIL: 接受了未声明的服务操作\n' >&2
  exit 1
fi

DRY_RUN=0
systemctl() {
  if [[ "$1" == "show" && "$4" == "Type" ]]; then
    printf 'oneshot\n'
  elif [[ "$1" == "show" && "$4" == "Result" ]]; then
    printf 'success\n'
  else
    return 1
  fi
}
services_apply_action apt-daily.service start >/dev/null || {
  printf 'FAIL: 成功完成的 oneshot 服务被误判为未运行\n' >&2
  exit 1
}

printf 'PASS: services\n'
