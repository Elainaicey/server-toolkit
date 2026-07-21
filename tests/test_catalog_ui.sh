#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
# catalog.sh 与 ui.sh 在加载后消费这些测试夹具变量。
# shellcheck disable=SC2034
SOFTWARE_CATALOG="$CONFIG_DIR/software.tsv"
# shellcheck disable=SC2034
SERVERCTL_VERSION=0.1.0
# shellcheck disable=SC2034
NO_COLOR=1

. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/ui.sh"

command_exists() { return 1; }
software_oh_my_zsh_installed() { return 1; }
software_oh_my_zsh_version() { :; }
software_prompt_installed() { return 1; }
software_prompt_version() { :; }
package_installed() { [[ "$1" == "jq" ]]; }
package_installed_version() { [[ "$1" == "jq" ]] && printf '1.6-2.1'; }
package_candidate_version() { [[ "$1" == "jq" ]] && printf '1.7.1-1'; }
package_has_update() { [[ "$1" == "jq" ]]; }
. "$ROOT_DIR/src/core/catalog.sh"

output="$(catalog_item_menu jq </dev/null)"
grep -q '软件信息' <<<"$output" || { printf 'FAIL: 软件详情缺少信息面板\n' >&2; exit 1; }
grep -q '当前版本.*1.6-2.1' <<<"$output" || { printf 'FAIL: 软件详情缺少当前版本\n' >&2; exit 1; }
grep -q '仓库候选版本.*1.7.1-1' <<<"$output" || { printf 'FAIL: 软件详情缺少候选版本\n' >&2; exit 1; }
grep -q '可更新' <<<"$output" || { printf 'FAIL: 软件详情没有识别更新状态\n' >&2; exit 1; }
grep -q '\[2\].*更新' <<<"$output" || { printf 'FAIL: 软件详情缺少更新操作\n' >&2; exit 1; }

printf 'PASS: catalog ui\n'
