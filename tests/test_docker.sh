#!/usr/bin/env bash
# Docker 命令由被测 Compose 上下文解析函数间接调用。
# shellcheck disable=SC2317,SC2329
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/features/apps/docker.sh"

docker_compose_project_valid edge-proxy || {
  printf 'FAIL: 正常 Compose 项目名被拒绝\n' >&2
  exit 1
}
if docker_compose_project_valid '../project' || docker_compose_project_valid 'project;reboot'; then
  printf 'FAIL: 接受了危险 Compose 项目名\n' >&2
  exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
touch "$test_root/compose.yml"
docker() {
  if [[ "$1" == "ps" ]]; then
    printf 'container-id\n'
  elif [[ "$1" == "inspect" && "$3" == *working_dir* ]]; then
    printf '%s\n' "$test_root"
  elif [[ "$1" == "inspect" && "$3" == *config_files* ]]; then
    printf '%s\n' "$test_root/compose.yml"
  fi
}

context_output="$(docker_compose_context edge-proxy)"
[[ "$context_output" == "$test_root"$'\n'"$test_root/compose.yml" ]] || {
  printf 'FAIL: Compose 项目上下文解析错误\n' >&2
  exit 1
}

printf 'PASS: docker\n'
