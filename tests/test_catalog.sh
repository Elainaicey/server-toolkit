#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
SOFTWARE_CATALOG="$CONFIG_DIR/software.tsv"

# shellcheck source=../src/core/runtime.sh
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/ui.sh"
runtime_colors

package_installed() { return 1; }
command_exists() { return 1; }
# shellcheck source=../src/core/catalog.sh
. "$ROOT_DIR/src/core/catalog.sh"

record="$(catalog_record python-venv)"
IFS='|' read -r id _category _name _description packages handler <<<"$record"
[[ "$id" == "python-venv" && "$packages" == "python3-venv" && -z "$handler" ]] || die "python-venv 映射错误"

duplicates="$(catalog_rows | awk -F '|' '{count[$1]++} END {for (id in count) if (count[id] > 1) print id}')"
[[ -z "$duplicates" ]] || die "存在重复 ID：$duplicates"

while IFS='|' read -r id category name description packages handler; do
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "无效 ID：$id"
  [[ -n "$category" && -n "$name" && -n "$description" ]] || die "目录字段为空：$id"
  case "$handler" in
    "") [[ -n "$packages" && "$packages" != *' '* ]] || die "普通软件必须精确映射一个包：$id" ;;
    docker_official|caddy_official) [[ -z "$packages" ]] || die "专用安装器不应同时声明包：$id" ;;
    *) die "未知安装器：$id -> $handler" ;;
  esac
done < <(catalog_rows)

captured=""
confirm() { return 0; }
require_root() { :; }
audit() { :; }
package_install() { captured="package:$1"; }
software_install_docker() { captured="handler:docker"; }
software_install_caddy() { captured="handler:caddy"; }

catalog_install jq >/dev/null
[[ "$captured" == "package:jq" ]] || die "普通软件没有精确分发到单个包"
catalog_install docker >/dev/null
[[ "$captured" == "handler:docker" ]] || die "Docker 专用安装器分发错误"

printf 'PASS: catalog\n'
