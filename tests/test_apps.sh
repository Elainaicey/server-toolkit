#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/features/apps.sh"

[[ "$(apps_service_record 1)" == 'Docker|docker.service|docker' ]] || {
  printf 'FAIL: Docker 应用服务映射错误\n' >&2
  exit 1
}
[[ "$(apps_service_record 9)" == '3x-ui|x-ui.service|' ]] || {
  printf 'FAIL: 3x-ui 应用服务映射错误\n' >&2
  exit 1
}
[[ "$(apps_service_catalog | awk -F '|' '{print $2}' | sort -u | wc -l | tr -d ' ')" == "9" ]] || {
  printf 'FAIL: 应用服务名称不唯一\n' >&2
  exit 1
}

printf 'PASS: apps\n'
