#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
SERVER_TOOLKIT_BACKUP_ROOT="$TEST_ROOT/backups"

. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/backup.sh"

mkdir -p "$SERVER_TOOLKIT_BACKUP_ROOT/20260719-120000-42/etc"
printf '/etc/example.conf\n' > "$SERVER_TOOLKIT_BACKUP_ROOT/20260719-120000-42/manifest.txt"
printf 'original\n' > "$SERVER_TOOLKIT_BACKUP_ROOT/20260719-120000-42/etc/example.conf"

[[ "$(backup_manifest 20260719-120000-42)" == "/etc/example.conf" ]] || {
  printf 'FAIL: 无法读取有效备份清单\n' >&2
  exit 1
}
if backup_manifest '../etc' >/dev/null 2>&1; then
  printf 'FAIL: 接受了危险快照名\n' >&2
  exit 1
fi

printf 'PASS: backup\n'
