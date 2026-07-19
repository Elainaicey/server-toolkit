#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/features/software.sh"

DRY_RUN=1
removed=""
confirmations=0
package_installed() { [[ "$1" == "containerd" ]]; }
confirm() { confirmations=$((confirmations + 1)); return 0; }
package_remove() { removed="$1"; }
package_install() { :; }
package_invalidate_index() { :; }

software_install_docker >/dev/null 2>&1
[[ "$removed" == "containerd" && "$confirmations" -eq 1 ]] || {
  printf 'FAIL: Docker 冲突包没有经过单独确认和移除\n' >&2
  exit 1
}

printf 'PASS: software\n'
