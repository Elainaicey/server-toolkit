#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/core.sh
. "$ROOT_DIR/lib/core.sh"

valid_port 22 || { printf 'FAIL: 22 应为有效端口\n' >&2; exit 1; }
valid_port 65535 || { printf 'FAIL: 65535 应为有效端口\n' >&2; exit 1; }
if valid_port 0 || valid_port 65536 || valid_port abc; then
  printf 'FAIL: 无效端口被接受\n' >&2
  exit 1
fi

path_is_safe_managed_target /opt/server-toolkit || { printf 'FAIL: 正常安装目录被拒绝\n' >&2; exit 1; }
if path_is_safe_managed_target / || path_is_safe_managed_target /opt || path_is_safe_managed_target /var/../etc; then
  printf 'FAIL: 危险目录被接受\n' >&2
  exit 1
fi

printf 'PASS: safety\n'
