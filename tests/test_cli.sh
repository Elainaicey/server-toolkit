#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../serverctl.sh
. "$ROOT_DIR/serverctl.sh"

captured=""
platform_detect() { :; }
catalog_install() { captured="$1"; }
catalog_print() { captured="list:${1:-}"; }

main install jq --dry-run
[[ "$captured" == "jq" && "$DRY_RUN" -eq 1 ]] || { printf 'FAIL: 单项安装参数解析错误\n' >&2; exit 1; }

main list python
[[ "$captured" == "list:python" ]] || { printf 'FAIL: list 参数解析错误\n' >&2; exit 1; }

if (main install curl jq >/dev/null 2>&1); then
  printf 'FAIL: CLI 接受了多个软件 ID\n' >&2
  exit 1
fi

printf 'PASS: cli\n'
