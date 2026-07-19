#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

# serverctl.sh 带直接执行保护，测试可只加载函数而不启动菜单。
# shellcheck source=../serverctl.sh
. "$ROOT_DIR/serverctl.sh"

CAPTURED_ITEMS=()
CAPTURED_FILTER=""
toolkit_init_runtime() { :; }
require_root() { :; }
detect_system() { OS_FAMILY="debian"; OS_ID="debian"; PM="apt-get"; }
pkg_update_index() { :; }
catalog_install_items() { CAPTURED_ITEMS=("$@"); }
catalog_print() { CAPTURED_FILTER="${1:-}"; }

main install curl jq --dry-run
[[ "$DRY_RUN" -eq 1 ]] || { printf 'FAIL: --dry-run 未被解析\n' >&2; exit 1; }
[[ "${#CAPTURED_ITEMS[@]}" -eq 2 && "${CAPTURED_ITEMS[0]}" == "curl" && "${CAPTURED_ITEMS[1]}" == "jq" ]] || {
  printf 'FAIL: 精确安装参数解析错误\n' >&2
  exit 1
}

main list runtime
[[ "$CAPTURED_FILTER" == "runtime" ]] || { printf 'FAIL: list 筛选参数解析错误\n' >&2; exit 1; }

printf 'PASS: cli\n'
