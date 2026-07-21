#!/usr/bin/env bash
# 本文件定义的全局变量均为被加载健康巡检模块消费的测试夹具。
# shellcheck disable=SC2034
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/ui.sh"
. "$ROOT_DIR/src/core/platform.sh"
. "$ROOT_DIR/src/features/system.sh"

NO_COLOR=1
SERVERCTL_VERSION=0.1.0
runtime_locale
runtime_colors

platform_detect() {
  OS_NAME='Debian GNU/Linux 13 (trixie)'; ARCH=amd64; VIRTUALIZATION=kvm
  CPU_CORES=2; MEMORY_MB=2048; MEMORY_USED_MB=512
  ROOT_USED_PERCENT=20; LOAD_AVERAGE='0.10 0.05 0.01'
}
dpkg() { return 0; }
df() {
  case "$1" in
    -Pm) printf 'Filesystem 1M-blocks Used Available Use%% Mounted\n/dev/vda 10000 2000 8000 20%% /\n' ;;
    -Pi) printf 'Filesystem Inodes IUsed IFree IUse%% Mounted\n/dev/vda 100000 1000 99000 1%% /\n' ;;
  esac
}
systemctl() { return 0; }
journalctl() { return 0; }
package_upgradable_count() { printf '0'; }
getent() { return 0; }
curl() { return 0; }
timedatectl() { printf 'yes\n'; }
ufw() { printf 'Status: active\n'; }
sshd() { printf 'passwordauthentication no\npermitrootlogin prohibit-password\n'; }
command_exists() {
  case "$1" in curl|timedatectl|ufw|sshd) return 0 ;; *) return 1 ;; esac
}

output="$(system_health_report)"
grep -q '系统健康巡检' <<<"$output" || { printf 'FAIL: 健康巡检页面缺失\n' >&2; exit 1; }
grep -q 'dpkg 软件包状态正常' <<<"$output" || { printf 'FAIL: 软件包健康项缺失\n' >&2; exit 1; }
grep -q 'HTTPS 出站连接正常' <<<"$output" || { printf 'FAIL: 网络健康项缺失\n' >&2; exit 1; }
grep -Eq '关注[[:space:]]+0' <<<"$output" || { printf 'FAIL: 正常环境产生了健康警告\n' >&2; exit 1; }
grep -q '当前检查项全部正常' <<<"$output" || { printf 'FAIL: 健康结论错误\n' >&2; exit 1; }

printf 'PASS: health\n'
