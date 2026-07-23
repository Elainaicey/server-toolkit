#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../src/core/runtime.sh
. "$ROOT_DIR/src/core/runtime.sh"
# shellcheck source=../src/features/system/processes.sh
. "$ROOT_DIR/src/features/system/processes.sh"

valid_pid 2 || { printf 'FAIL: 正常 PID 被拒绝\n' >&2; exit 1; }
valid_pid 4194304 || { printf 'FAIL: 最大 PID 被拒绝\n' >&2; exit 1; }
if valid_pid 0 || valid_pid 1 || valid_pid -2 || valid_pid '2;reboot'; then
  printf 'FAIL: 接受了无效 PID\n' >&2
  exit 1
fi

valid_nice_value -20 || { printf 'FAIL: nice=-20 被拒绝\n' >&2; exit 1; }
valid_nice_value 19 || { printf 'FAIL: nice=19 被拒绝\n' >&2; exit 1; }
if valid_nice_value -21 || valid_nice_value 20 || valid_nice_value '0;reboot'; then
  printf 'FAIL: 接受了无效 nice 值\n' >&2
  exit 1
fi

process_is_protected 1 || { printf 'FAIL: PID 1 未受保护\n' >&2; exit 1; }
process_is_protected "$$" || { printf 'FAIL: 当前测试进程未受保护\n' >&2; exit 1; }
process_exists "$$" || { printf 'FAIL: 无法识别当前进程\n' >&2; exit 1; }

printf 'PASS: processes\n'
