#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/features/software.sh"

# software.sh 与 runtime.sh 在加载后消费这些测试夹具。
# shellcheck disable=SC2034
DRY_RUN=1
removed=""
confirmations=0
# software_install_docker 通过功能模块间接调用该测试桩。
# ShellCheck 0.9 使用 SC2317，新版使用 SC2329 标记间接测试桩。
# shellcheck disable=SC2317,SC2329
package_installed() { [[ "$1" == "containerd" ]]; }
confirm() { confirmations=$((confirmations + 1)); return 0; }
package_remove() { removed="$1"; }
package_install() { :; }
package_install_latest() { :; }
package_invalidate_index() { :; }

software_install_docker >/dev/null 2>&1
[[ "$removed" == "containerd" && "$confirmations" -eq 1 ]] || {
  printf 'FAIL: Docker 冲突包没有经过单独确认和移除\n' >&2
  exit 1
}

package_installed() { [[ "$1" == "docker.io" ]]; }
package_upgrade() { removed="upgrade:$1"; }
software_update_docker >/dev/null
[[ "$removed" == "upgrade:docker.io" ]] || {
  printf 'FAIL: 系统仓库 Docker 没有沿用其现有来源更新\n' >&2
  exit 1
}

printf 'PASS: software\n'
