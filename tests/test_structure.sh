#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

required=(
  .gitattributes
  README.md
  VERSION
  install.sh
  LICENSE
  .github/assets/badges/version.svg
  .github/assets/badges/shell.svg
  .github/assets/badges/platform.svg
  .github/assets/badges/language.svg
  .github/assets/badges/license.svg
  .github/CONTRIBUTING.md
  .github/SECURITY.md
  docs/CHANGELOG.md
  bin/serverctl
  config/software.tsv
  config/official-releases.tsv
  scripts/install.sh
  scripts/check-repository.sh
  scripts/check-shell.sh
  scripts/check-tests.sh
  scripts/release-check.sh
  .github/workflows/release.yml
  docs/RELEASE.md
  src/core/runtime.sh
  src/core/validation.sh
  src/features/software/catalog.sh
  src/features/software/catalog/query.sh
  src/features/software/catalog/presentation.sh
  src/features/software/catalog/actions.sh
  src/features/software/catalog/views.sh
  src/features/dashboard.sh
  src/features/security.sh
  src/features/security/overview.sh
  src/features/security/exposure.sh
  src/features/security/activity.sh
  src/features/security/fail2ban.sh
  src/features/security/certificates.sh
  src/features/security/firewall.sh
  src/features/security/ssh.sh
  src/features/security/menu.sh
  src/features/services.sh
  src/features/services/overview.sh
  src/features/services/journal.sh
  src/features/services/units.sh
  src/features/services/audit.sh
  src/features/services/menu.sh
  src/features/system/settings.sh
  src/features/system/diagnostics.sh
  src/features/system/menu.sh
  src/features/system/packages.sh
  src/features/system/storage.sh
  src/features/system/triage.sh
  src/features/network/diagnostics.sh
  src/features/network/overview.sh
  src/features/network/tuning.sh
  src/features/network/menu.sh
  src/features/software.sh
  src/features/software/oh-my-zsh.sh
  src/features/software/prompts.sh
  src/features/software/releases.sh
  src/features/apps.sh
  src/features/apps/menu.sh
  src/features/apps/services.sh
  src/features/apps/services/metadata.sh
  src/features/apps/services/inspect.sh
  src/features/apps/services/actions.sh
  src/features/apps/services/menu.sh
  src/features/apps/docker.sh
  src/features/apps/docker/inventory.sh
  src/features/apps/docker/compose.sh
  src/features/apps/docker/containers.sh
  src/features/apps/docker/menu.sh
  src/features/maintenance.sh
  src/features/maintenance/doctor.sh
  src/features/apps/docker/volumes.sh
)
for path in "${required[@]}"; do
  [[ -e "$ROOT_DIR/$path" ]] || { printf 'FAIL: 缺少 %s\n' "$path" >&2; exit 1; }
done

for attribute in \
  '* text=auto eol=lf' \
  '.gitattributes text eol=lf' \
  '*.sh text eol=lf' \
  'bin/* text eol=lf' \
  '*.tsv text eol=lf' \
  '*.md text eol=lf' \
  '*.yml text eol=lf' \
  '*.svg text eol=lf'; do
  grep -Fqx "$attribute" "$ROOT_DIR/.gitattributes" || {
    printf 'FAIL: .gitattributes 缺少 LF 规则：%s\n' "$attribute" >&2
    exit 1
  }
done

for moved_document in CHANGELOG.md CONTRIBUTING.md SECURITY.md; do
  [[ ! -e "$ROOT_DIR/$moved_document" ]] || { printf 'FAIL: 文档仍位于根目录：%s\n' "$moved_document" >&2; exit 1; }
done

[[ ! -e "$ROOT_DIR/src/features/docker.sh" ]] || {
  printf 'FAIL: Docker 仍直接放在 features 根目录\n' >&2
  exit 1
}

for entry in \
  src/features/security.sh \
  src/features/services.sh \
  src/features/apps/docker.sh \
  src/features/software/catalog.sh \
  src/features/network.sh \
  src/features/system.sh \
  src/features/apps.sh \
  src/features/apps/services.sh; do
  lines="$(wc -l < "$ROOT_DIR/$entry" | tr -d '[:space:]')"
  (( lines <= 20 )) || {
    printf 'FAIL: 领域入口重新堆积了业务实现：%s (%s 行)\n' "$entry" "$lines" >&2
    exit 1
  }
done

for legacy in serverctl.sh lib features catalog profiles modules; do
  [[ ! -e "$ROOT_DIR/$legacy" ]] || { printf 'FAIL: 旧路径仍然存在：%s\n' "$legacy" >&2; exit 1; }
done

for removed_feature in \
  src/features/system/accounts.sh \
  src/features/services/timers.sh \
  tests/test_accounts.sh \
  tests/test_health.sh; do
  [[ ! -e "$ROOT_DIR/$removed_feature" ]] || {
    printf 'FAIL: root-only 精简内容仍然存在：%s\n' "$removed_feature" >&2
    exit 1
  }
done

[[ "$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")" == "0.3.0" ]] || {
  printf 'FAIL: VERSION 不是 0.3.0\n' >&2
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
grep -q 'ui_display_width' "$ROOT_DIR/src/core/ui.sh" || {
  printf 'FAIL: UI 没有按终端显示宽度处理中文对齐\n' >&2
  exit 1
}

printf 'PASS: structure\n'
