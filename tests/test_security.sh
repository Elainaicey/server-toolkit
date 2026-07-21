#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

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

printf 'PASS: security\n'
