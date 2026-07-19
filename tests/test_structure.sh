#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

[[ ! -d "$ROOT_DIR/profiles" ]] || { printf 'FAIL: profiles 目录仍然存在\n' >&2; exit 1; }
[[ ! -d "$ROOT_DIR/modules" ]] || { printf 'FAIL: modules 目录仍然存在\n' >&2; exit 1; }
grep -q 'SERVERCTL_VERSION="0.1.0"' "$ROOT_DIR/serverctl.sh" || { printf 'FAIL: 版本不是 0.1.0\n' >&2; exit 1; }

if grep -R -E 'PROFILE_|ASSUME_YES|install_bundle|--profile' \
  "$ROOT_DIR/serverctl.sh" "$ROOT_DIR/install.sh" "$ROOT_DIR/lib" "$ROOT_DIR/features" "$ROOT_DIR/catalog"; then
  printf 'FAIL: 运行时代码仍包含旧兼容或无人值守逻辑\n' >&2
  exit 1
fi
if grep -E -- '--yes' "$ROOT_DIR/serverctl.sh" "$ROOT_DIR/install.sh"; then
  printf 'FAIL: 入口仍包含无人值守确认选项\n' >&2
  exit 1
fi
if grep -E 'ufw|firewall|ssh' "$ROOT_DIR/features/software.sh"; then
  printf 'FAIL: 软件安装器联动了防火墙或 SSH\n' >&2
  exit 1
fi

printf 'PASS: structure\n'
