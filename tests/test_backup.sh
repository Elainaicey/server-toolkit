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
backup_verify 20260719-120000-42 >/dev/null || {
  printf 'FAIL: 有效备份没有通过完整性校验\n' >&2
  exit 1
}
if backup_manifest '../etc' >/dev/null 2>&1; then
  printf 'FAIL: 接受了危险快照名\n' >&2
  exit 1
fi
if backup_verify '../etc' >/dev/null 2>&1; then
  printf 'FAIL: 完整性校验接受了危险快照名\n' >&2
  exit 1
fi

DRY_RUN=1
backup_restore 20260719-120000-42 /etc/example.conf >/dev/null
backup_delete 20260719-120000-42 >/dev/null
[[ -d "$SERVER_TOOLKIT_BACKUP_ROOT/20260719-120000-42" ]] || {
  printf 'FAIL: dry-run 删除了备份\n' >&2
  exit 1
}

# backup_delete 从运行时读取该全局开关。
# shellcheck disable=SC2034
DRY_RUN=0
backup_delete 20260719-120000-42
[[ ! -e "$SERVER_TOOLKIT_BACKUP_ROOT/20260719-120000-42" ]] || {
  printf 'FAIL: 没有删除明确选择的备份\n' >&2
  exit 1
}

printf 'PASS: backup\n'
