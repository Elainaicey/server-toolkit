#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/core.sh
. "$ROOT_DIR/lib/core.sh"
. "$ROOT_DIR/lib/platform.sh"

updates=0
captured=()
package_installed() { [[ "$1" == "curl" ]]; }
package_update_index() { updates=$((updates + 1)); }
apt_run() { captured=("$@"); }

package_install curl jq >/dev/null
[[ "$updates" -eq 1 ]] || { printf 'FAIL: 缺失包没有触发一次索引刷新\n' >&2; exit 1; }
[[ "${#captured[@]}" -eq 3 && "${captured[0]}" == "install" && "${captured[1]}" == "-y" && "${captured[2]}" == "jq" ]] || {
  printf 'FAIL: 已安装的包没有被排除\n' >&2
  exit 1
}

updates=0
captured=()
package_install curl >/dev/null
[[ "$updates" -eq 0 && "${#captured[@]}" -eq 0 ]] || {
  printf 'FAIL: 已安装软件仍触发了 APT\n' >&2
  exit 1
}

printf 'PASS: package\n'
