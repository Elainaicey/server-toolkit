#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

for profile in "$ROOT_DIR"/profiles/*.conf; do
  unset PROFILE_NAME PROFILE_INSTALL_BASE PROFILE_PACKAGES PROFILE_MODULES
  # shellcheck source=/dev/null
  . "$profile"
  [[ -n "${PROFILE_NAME:-}" ]] || { printf 'FAIL: %s 缺少 PROFILE_NAME\n' "$profile" >&2; exit 1; }
  [[ "${PROFILE_INSTALL_BASE:-}" == "0" ]] || { printf 'FAIL: %s 必须显式禁用隐式基础集合\n' "$profile" >&2; exit 1; }
done

printf 'PASS: profiles\n'
