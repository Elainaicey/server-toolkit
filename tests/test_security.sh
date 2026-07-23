#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=../src/core/runtime.sh
. "$ROOT_DIR/src/core/runtime.sh"
# shellcheck source=../src/features/security.sh
. "$ROOT_DIR/src/features/security.sh"

now=1767225600
[[ "$(security_certificate_days_left '@1768089600' "$now")" == "10" ]] || {
  printf 'FAIL: 证书剩余天数计算错误\n' >&2
  exit 1
}
[[ "$(security_certificate_days_left '@1767139200' "$now")" == "-1" ]] || {
  printf 'FAIL: 过期证书天数计算错误\n' >&2
  exit 1
}
if security_certificate_days_left 'not-a-date' "$now" >/dev/null; then
  printf 'FAIL: 无效证书时间没有被拒绝\n' >&2
  exit 1
fi

fail2ban-client() {
  case "${2:-}" in
    sshd) printf 'Currently banned: 2\n' ;;
    nginx) printf 'Currently banned: 1\n' ;;
  esac
}
[[ "$(security_fail2ban_total_banned $'sshd\nnginx')" == "3" ]] || {
  printf 'FAIL: Fail2ban 封禁数量汇总错误\n' >&2
  exit 1
}

captured=""
command_exists() { [[ "$1" == "ufw" ]]; }
read_input() {
  case "$1" in
    "端口或范围") printf '8443' ;;
    "协议") printf '2' ;;
    "来源 IP/CIDR；any 表示任意来源") printf 'any' ;;
    *) printf '%s' "${2:-}" ;;
  esac
}
confirm() { return 0; }
require_root() { :; }
run() { captured="$1 $2 $3"; }
ui_page() { :; }
ui_action() { :; }
ui_section() { :; }
ui_kv() { :; }
ui_success() { :; }

security_firewall_rule >/dev/null
[[ "$captured" == "ufw allow 8443/udp" ]] || {
  printf 'FAIL: UDP 防火墙规则构造错误\n' >&2
  exit 1
}

printf 'PASS: security\n'
