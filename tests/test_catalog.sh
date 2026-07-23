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
software_oh_my_zsh_installed() { return 1; }
software_oh_my_zsh_version() { :; }
software_prompt_installed() { return 1; }
software_prompt_version() { :; }
software_release_managed() { return 1; }
software_release_installed() { return 1; }
software_release_integrity() { return 1; }
software_release_supported() { return 0; }
software_release_version() { :; }
software_release_homepage() { printf 'https://example.com'; }
software_release_repository() { printf 'owner/repo'; }
software_release_target() { printf '/usr/local/bin/example'; }
software_target_user() { printf 'tester'; }
software_target_home() { printf '/home/tester'; }
software_oh_my_zsh_path() { printf '/home/tester/.oh-my-zsh'; }
# shellcheck source=../src/features/software/catalog.sh
. "$ROOT_DIR/src/features/software/catalog.sh"

record="$(catalog_record python-venv)"
IFS='|' read -r id _category _name _description packages handler <<<"$record"
[[ "$id" == "python-venv" && "$packages" == "python3-venv" && -z "$handler" ]] || die "python-venv 映射错误"

record="$(catalog_record podman)"
IFS='|' read -r id category _name _description packages handler <<<"$record"
[[ "$id" == "podman" && "$category" == "容器" && "$packages" == "podman" && -z "$handler" ]] || die "podman 映射错误"

catalog_total="$(catalog_rows | wc -l | tr -d '[:space:]')"
(( catalog_total >= 168 )) || die "软件目录条目不足：$catalog_total"

record="$(catalog_record oh-my-zsh)"
IFS='|' read -r id category _name _description packages handler <<<"$record"
[[ "$id" == "oh-my-zsh" && "$category" == "终端美化" && -z "$packages" && "$handler" == "oh_my_zsh" ]] || die "Oh My Zsh 专用安装器映射错误"

record="$(catalog_record ripgrep)"
IFS='|' read -r id category _name _description packages handler <<<"$record"
[[ "$id" == "ripgrep" && "$category" == "命令行" && "$packages" == "ripgrep" &&
  "$handler" == "official_release" ]] || die "ripgrep 官方 Release 映射错误"

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
    docker_official|caddy_official|oh_my_zsh|starship_prompt|oh_my_posh_prompt|spaceship_prompt) [[ -z "$packages" ]] || die "专用安装器不应同时声明包：$id" ;;
    official_release) software_release_record="$(awk -F '|' -v wanted="$id" '!/^#/ && $1 == wanted {print}' "$CONFIG_DIR/official-releases.tsv")"; [[ -n "$software_release_record" ]] || die "缺少官方 Release 元数据：$id" ;;
    *) die "未知安装器：$id -> $handler" ;;
  esac
done < <(catalog_rows)

release_total=0
while IFS='|' read -r id repository command amd64_asset arm64_asset homepage; do
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "无效 Release ID：$id"
  [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "无效 GitHub 仓库：$id"
  [[ "$command" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "无效 Release 命令：$id"
  [[ "$amd64_asset" == *.tar.gz && "$arm64_asset" == *.tar.gz ]] || die "Release 资产格式无效：$id"
  [[ "$homepage" == "https://github.com/$repository" ]] || die "Release 项目主页与仓库不一致：$id"
  record="$(catalog_record "$id")" || die "Release 元数据没有软件条目：$id"
  IFS='|' read -r _ _ _ _ _ handler <<<"$record"
  [[ "$handler" == "official_release" ]] || die "Release 元数据没有使用专用 handler：$id"
  release_total=$((release_total + 1))
done < <(awk -F '|' '!/^#/ && NF == 6' "$CONFIG_DIR/official-releases.tsv")
(( release_total >= 12 )) || die "官方 Release 条目不足：$release_total"

package_candidate_version() { [[ "$1" == "jq" ]] && printf '(none)' || printf '1.0.0'; }
record="$(catalog_record jq)"
[[ "$(catalog_state "$record")" == "unavailable" ]] || die "没有识别当前软件源不可用的普通软件"
package_candidate_version() { printf '1.0.0'; }

software_oh_my_zsh_installed() { return 0; }
record="$(catalog_record oh-my-zsh)"
[[ "$(catalog_state "$record")" == "managed" ]] || die "官方来源软件被错误标记为已经确认最新"
software_oh_my_zsh_installed() { return 1; }

captured=""
installed_state=0
confirm() { return 0; }
require_root() { :; }
audit() { :; }
catalog_installed() { [[ "$installed_state" -eq 1 ]]; }
catalog_installed_version() { printf '1.0.0'; }
package_install_latest() { captured="package:$1"; installed_state=1; }
software_install_docker() { captured="handler:docker"; installed_state=1; }
software_install_caddy() { captured="handler:caddy"; installed_state=1; }
software_install_oh_my_zsh() { captured="handler:oh-my-zsh"; installed_state=1; }
software_install_starship() { captured="handler:starship"; installed_state=1; }
software_install_oh_my_posh() { captured="handler:oh-my-posh"; installed_state=1; }
software_install_spaceship() { captured="handler:spaceship"; installed_state=1; }
software_install_release() { captured="handler:release:$1"; installed_state=1; }

catalog_install jq >/dev/null
[[ "$captured" == "package:jq" ]] || die "普通软件没有精确分发到单个包"
installed_state=0
catalog_install docker >/dev/null
[[ "$captured" == "handler:docker" ]] || die "Docker 专用安装器分发错误"
installed_state=0
catalog_install oh-my-zsh >/dev/null
[[ "$captured" == "handler:oh-my-zsh" ]] || die "Oh My Zsh 专用安装器分发错误"
installed_state=0
catalog_install starship >/dev/null
[[ "$captured" == "handler:starship" ]] || die "Starship 专用安装器分发错误"

installed_state=0
package_install_latest() { return 1; }
if catalog_install jq >/dev/null 2>&1; then
  die "普通软件安装失败没有向上返回"
fi
package_install_latest() { captured="package:$1"; installed_state=1; }

installed_state=1
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
