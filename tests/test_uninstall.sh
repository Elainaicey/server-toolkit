#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
INSTALLER="$ROOT_DIR/scripts/install.sh"

bash "$INSTALLER" --help | grep -q -- '--purge-data' || {
  printf 'FAIL: 卸载器帮助缺少彻底清除选项\n' >&2
  exit 1
}
grep -Fq 'rm -rf -- "$BACKUP_ROOT" "$LOG_ROOT" "$STATE_ROOT"' "$INSTALLER" || {
  printf 'FAIL: 彻底清除没有覆盖全部项目数据目录\n' >&2
  exit 1
}
grep -Fq 'exec bash "$installer" --uninstall --purge-data --dir "$ROOT_DIR" --bin "$bin_path"' "$ROOT_DIR/src/features/maintenance.sh" || {
  printf 'FAIL: 交互菜单没有连接彻底清除流程\n' >&2
  exit 1
}

printf 'PASS: uninstall\n'
