#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/features/maintenance/doctor.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/safe"
chmod 0755 "$test_root/safe"
toolkit_mode_safe 0755 || {
  printf 'FAIL: 拒绝了安全的目录权限\n' >&2
  exit 1
}
if toolkit_mode_safe 0777 || toolkit_mode_safe invalid; then
  printf 'FAIL: 接受了任何用户都可写的程序目录\n' >&2
  exit 1
fi

toolkit_version_valid 0.3.0 || { printf 'FAIL: 正常语义版本被拒绝\n' >&2; exit 1; }
if toolkit_version_valid latest; then
  printf 'FAIL: 接受了无效项目版本\n' >&2
  exit 1
fi

printf '# header\none|two|three|four|five|six\n' >"$test_root/catalog.tsv"
toolkit_catalog_shape_valid "$test_root/catalog.tsv" || {
  printf 'FAIL: 正常六字段目录被拒绝\n' >&2
  exit 1
}
printf 'one|two|three\n' >>"$test_root/catalog.tsv"
if toolkit_catalog_shape_valid "$test_root/catalog.tsv"; then
  printf 'FAIL: 接受了字段数错误的软件目录\n' >&2
  exit 1
fi

printf 'PASS: toolkit doctor\n'
