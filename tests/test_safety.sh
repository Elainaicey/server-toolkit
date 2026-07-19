#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/core.sh
. "$ROOT_DIR/lib/core.sh"

valid_port 22 || { printf 'FAIL: 22 应有效\n' >&2; exit 1; }
valid_port 65535 || { printf 'FAIL: 65535 应有效\n' >&2; exit 1; }
if valid_port 0 || valid_port 65536 || valid_port text; then
  printf 'FAIL: 接受了无效端口\n' >&2
  exit 1
fi

safe_managed_path /opt/server-toolkit || { printf 'FAIL: 正常路径被拒绝\n' >&2; exit 1; }
if safe_managed_path / || safe_managed_path /opt || safe_managed_path /var/../etc; then
  printf 'FAIL: 接受了危险路径\n' >&2
  exit 1
fi

printf 'PASS: safety\n'
