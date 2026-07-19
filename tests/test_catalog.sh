#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
CATALOG_FILE="$ROOT_DIR/catalog/packages.tsv"
OS_FAMILY="debian"
OS_ID="debian"
INSTALLED=()

die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
log_warn() { :; }
log_step() { :; }
pkg_installed() { return 1; }
pkg_install_exact() { INSTALLED+=("$*"); }

# shellcheck source=../lib/catalog.sh
. "$ROOT_DIR/lib/catalog.sh"

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [[ "$actual" == "$expected" ]] || die "$message (expected='$expected', actual='$actual')"
}

record="$(catalog_record fd)"
assert_eq "fd-find" "$(catalog_packages_for_record "$record")" "Debian 软件包映射错误"

OS_FAMILY="rhel"
assert_eq "fd-find" "$(catalog_packages_for_record "$record")" "RHEL 软件包映射错误"
OS_FAMILY="debian"

catalog_install_items curl fd python-venv
assert_eq "curl" "${INSTALLED[0]}" "curl 应保持单项安装"
assert_eq "fd-find" "${INSTALLED[1]}" "fd 应映射到发行版包名"
assert_eq "python3-venv" "${INSTALLED[2]}" "python-venv 不应隐式安装完整 Python 工具链"

if catalog_record does-not-exist >/dev/null 2>&1; then
  die "未知 ID 不应匹配成功"
fi

duplicates="$(catalog_rows | awk -F '|' '{ count[$1]++ } END { for (id in count) if (count[id] > 1) print id }')"
[[ -z "$duplicates" ]] || die "软件目录存在重复 ID：$duplicates"

invalid="$(awk -F '|' '!/^#/ && (NF != 5 || $1 !~ /^[a-z0-9][a-z0-9-]*$/) { print NR }' "$CATALOG_FILE")"
[[ -z "$invalid" ]] || die "软件目录格式错误：$invalid"

printf 'PASS: catalog\n'
