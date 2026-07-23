#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/features/system/storage.sh"

for path in /var /home /opt /srv /tmp; do
  system_storage_allowed_root "$path" || {
    printf 'FAIL: 正常存储扫描根目录被拒绝：%s\n' "$path" >&2
    exit 1
  }
done
if system_storage_allowed_root / || system_storage_allowed_root /etc ||
  system_storage_allowed_root /var/lib || system_storage_allowed_root '../var'; then
  printf 'FAIL: 存储扫描接受了未声明或危险目录\n' >&2
  exit 1
fi

printf 'PASS: storage\n'
