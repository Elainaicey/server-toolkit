#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
. "$ROOT_DIR/src/core/runtime.sh"
. "$ROOT_DIR/src/core/ui.sh"

# ui.sh 在加载后消费这些测试夹具变量。
# shellcheck disable=SC2034
SERVERCTL_VERSION="0.1.0"
# shellcheck disable=SC2034
NO_COLOR=1
runtime_locale
runtime_colors
output="$(ui_banner; ui_header "测试中心"; ui_item 1 "测试操作" "测试说明"; ui_panel_begin "信息"; ui_panel_kv "版本" "0.1.0"; ui_panel_end; ui_action 2 "更新" "warning"; ui_note "测试提示")"
grep -q 'SERVER TOOLKIT' <<<"$output" || { printf 'FAIL: UI 横幅缺失\n' >&2; exit 1; }
grep -q '测试操作' <<<"$output" || { printf 'FAIL: UI 菜单项缺失\n' >&2; exit 1; }
grep -q '╭─ 信息' <<<"$output" || { printf 'FAIL: UI 信息面板缺失\n' >&2; exit 1; }
grep -q '\[2\].*更新' <<<"$output" || { printf 'FAIL: UI 语义操作缺失\n' >&2; exit 1; }
[[ "$(ui_display_width "系统")" -eq 4 ]] || { printf 'FAIL: 中文显示宽度计算错误\n' >&2; exit 1; }
progress="$(ui_progress "内存" 50 100 MiB)"
grep -q '50%' <<<"$progress" || { printf 'FAIL: 资源进度条计算错误\n' >&2; exit 1; }
health_summary="$(ui_health_summary 12 2 1)"
grep -Eq '通过[[:space:]]+12.*关注[[:space:]]+2.*异常[[:space:]]+1' <<<"$health_summary" || {
  printf 'FAIL: 健康摘要布局错误\n' >&2
  exit 1
}
check_line="$(ui_check warn "需要关注")"
grep -q '! 需要关注' <<<"$check_line" || { printf 'FAIL: UI 检查状态组件错误\n' >&2; exit 1; }

printf 'PASS: ui\n'
