#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../bin/serverctl
. "$ROOT_DIR/bin/serverctl"

captured=""
platform_detect() { :; }
catalog_install() { captured="$1"; }
catalog_update() { captured="update:$1"; }
catalog_print() { captured="list:${1:-}"; }
toolkit_uninstall() { captured="uninstall"; }

main install jq --dry-run
[[ "$captured" == "jq" && "$DRY_RUN" -eq 1 ]] || { printf 'FAIL: 单项安装参数解析错误\n' >&2; exit 1; }

main list python
[[ "$captured" == "list:python" ]] || { printf 'FAIL: list 参数解析错误\n' >&2; exit 1; }

main update jq
[[ "$captured" == "update:jq" ]] || { printf 'FAIL: update 参数解析错误\n' >&2; exit 1; }

if (main install curl jq >/dev/null 2>&1); then
  printf 'FAIL: CLI 接受了多个软件 ID\n' >&2
  exit 1
fi

main uninstall
[[ "$captured" == "uninstall" ]] || { printf 'FAIL: uninstall 命令没有进入卸载流程\n' >&2; exit 1; }

printf 'PASS: cli\n'
