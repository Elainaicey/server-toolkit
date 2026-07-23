#!/usr/bin/env bash
# 本文件定义的全局变量均为被加载仪表盘模块消费的测试夹具。
# shellcheck disable=SC2034
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/ui.sh"
. "$ROOT_DIR/src/features/dashboard.sh"

NO_COLOR=1
SERVERCTL_VERSION=0.1.0
runtime_locale
runtime_colors

platform_detect() {
  OS_NAME='Debian GNU/Linux 13 (trixie)'; ARCH=amd64; VIRTUALIZATION=kvm
  UPTIME_TEXT='3 hours'; LOAD_AVERAGE='0.05 0.02 0.00'; CPU_CORES=1
  MEMORY_USED_MB=453; MEMORY_MB=967; SWAP_USED_MB=0; SWAP_MB=2048
}
command_exists() { [[ "$1" == ss || "$1" == docker ]]; }
package_upgradable_count() { printf '7'; }
service_state() { printf 'active'; }
service_exists() { [[ "$1" == "fail2ban.service" ]]; }
platform_firewall_active() { return 0; }
timedatectl() { [[ "$1" == "show" ]] && printf 'yes\n'; }
systemctl() {
  case "$1" in
    --failed) return 0 ;;
    --type=service) printf 'one\ntwo\n' ;;
  esac
}
ss() { printf 'one\ntwo\nthree\n'; }
docker() { printf 'one\ntwo\n'; }
df() {
  if [[ "$1" == '-Pm' ]]; then
    printf 'Filesystem 1M-blocks Used Available Use%% Mounted\n/dev/vda 10000 5300 4700 53%% /\n'
  fi
}

output="$(dashboard_show)"
grep -q '^│  系统              Debian GNU/Linux 13' <<<"$output" || {
  printf 'FAIL: 仪表盘中文标签没有按显示宽度对齐\n' >&2
  exit 1
}
grep -q '46%  453/967 MiB' <<<"$output" || { printf 'FAIL: 内存进度计算错误\n' >&2; exit 1; }
grep -q 'Docker            ● active · 2 个运行中' <<<"$output" || { printf 'FAIL: Docker 状态布局错误\n' >&2; exit 1; }

printf 'PASS: dashboard\n'
