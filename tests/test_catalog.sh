#!/usr/bin/env bash
# 测试替身与目录变量由随后 source 的 catalog 模块间接使用。
# shellcheck disable=SC2034,SC2317,SC2329
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
package_installed_version() { :; }
package_candidate_version() { printf '1.0.0'; }
package_has_update() { return 1; }
command_exists() { return 1; }
# shellcheck source=../src/core/catalog.sh
. "$ROOT_DIR/src/core/catalog.sh"

record="$(catalog_record python-venv)"
IFS='|' read -r id _category _name _description packages handler <<<"$record"
[[ "$id" == "python-venv" && "$packages" == "python3-venv" && -z "$handler" ]] || die "python-venv 映射错误"

record="$(catalog_record podman)"
IFS='|' read -r id category _name _description packages handler <<<"$record"
[[ "$id" == "podman" && "$category" == "容器" && "$packages" == "podman" && -z "$handler" ]] || die "podman 映射错误"

catalog_total="$(catalog_rows | wc -l | tr -d '[:space:]')"
(( catalog_total >= 100 )) || die "软件目录条目不足：$catalog_total"

network_total="$(catalog_category_rows 网络 | wc -l | tr -d '[:space:]')"
(( network_total >= 10 )) || die "网络分类条目不足：$network_total"
[[ -z "$(catalog_category_rows 网络 | awk -F '|' '$2 != "网络" {print}')" ]] || die "分类查询返回了其他分类"
grep -Eq '^基础\|[0-9]+$' < <(catalog_categories) || die "分类统计缺少基础分类"

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

package_installed() { [[ "$1" == "jq" ]]; }
package_installed_version() { printf '1.0.0'; }
package_candidate_version() { printf '1.1.0'; }
package_has_update() { [[ "$1" == "jq" ]]; }
package_invalidate_index() { :; }
package_update_index() { :; }
package_upgrade() { captured="update:$1"; }
catalog_update jq >/dev/null
[[ "$captured" == "update:jq" ]] || die "普通软件没有分发到单项更新流程"

printf 'PASS: catalog\n'
