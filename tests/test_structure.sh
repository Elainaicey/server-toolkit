#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

required=(
  bin/serverctl
  config/software.tsv
  scripts/install.sh
  src/core/runtime.sh
  src/core/catalog.sh
  src/features/dashboard.sh
  src/features/software.sh
  src/features/apps.sh
  src/features/apps/docker.sh
  src/features/maintenance.sh
)
for path in "${required[@]}"; do
  [[ -e "$ROOT_DIR/$path" ]] || { printf 'FAIL: 缺少 %s\n' "$path" >&2; exit 1; }
done

[[ ! -e "$ROOT_DIR/src/features/docker.sh" ]] || {
  printf 'FAIL: Docker 仍直接放在 features 根目录\n' >&2
  exit 1
}

for legacy in serverctl.sh lib features catalog profiles modules; do
  [[ ! -e "$ROOT_DIR/$legacy" ]] || { printf 'FAIL: 旧路径仍然存在：%s\n' "$legacy" >&2; exit 1; }
done

[[ "$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")" == "0.1.0" ]] || {
  printf 'FAIL: VERSION 不是 0.1.0\n' >&2
  exit 1
}

if grep -R -E 'PROFILE_|ASSUME_YES|install_bundle|--profile' \
  "$ROOT_DIR/bin" "$ROOT_DIR/src" "$ROOT_DIR/config" "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts/install.sh"; then
  printf 'FAIL: 运行时仍包含旧兼容、批量或无人值守逻辑\n' >&2
  exit 1
fi
if grep -E -- '--yes([[:space:]]|\))' "$ROOT_DIR/bin/serverctl" "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts/install.sh"; then
  printf 'FAIL: 用户入口仍提供无人值守确认选项\n' >&2
  exit 1
fi
if grep -E 'ufw|firewall|ssh' "$ROOT_DIR/src/features/software.sh"; then
  printf 'FAIL: 软件安装器联动了防火墙或 SSH\n' >&2
  exit 1
fi
grep -q -- '--purge-data' "$ROOT_DIR/scripts/install.sh" || {
  printf 'FAIL: 安装器缺少彻底清除选项\n' >&2
  exit 1
}

printf 'PASS: structure\n'
