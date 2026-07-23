#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../bin/serverctl
. "$ROOT_DIR/bin/serverctl"

captured=""
platform_detect() { :; }
catalog_install() { captured="$1"; }
catalog_update() { captured="update:$1"; }
catalog_print() { captured="list:${1:-}"; }
toolkit_uninstall() { captured="uninstall"; }
system_health_report() { captured="health"; }
system_package_health() { captured="updates"; }
system_disk_usage() { captured="storage"; }
service_exists() { return 0; }
unit_exists() { return 0; }
services_logs() { captured="logs:$1"; }
services_select() { captured="service:$1"; }
services_apply_action() { captured="service:$1:$2"; }
services_timer_select() { captured="timer:$1"; }
services_journal_info() { captured="journal"; }
system_swap_manage() { captured="swap"; }
docker_compose_manage() { captured="compose:$1"; }
system_accounts_menu() { captured="users"; }
account_exists() { return 0; }
system_account_select() { captured="user:$1"; }
process_exists() { return 0; }
system_process_select() { captured="process:$1"; }

main install jq --dry-run
[[ "$captured" == "jq" && "$DRY_RUN" -eq 1 ]] || { printf 'FAIL: 单项安装参数解析错误\n' >&2; exit 1; }

main list python
[[ "$captured" == "list:python" ]] || { printf 'FAIL: list 参数解析错误\n' >&2; exit 1; }

main update jq
[[ "$captured" == "update:jq" ]] || { printf 'FAIL: update 参数解析错误\n' >&2; exit 1; }

if (main install curl jq >/dev/null 2>&1); then
  printf 'FAIL: CLI 接受了多个软件 ID\n' >&2
  exit 1
fi

main health
[[ "$captured" == "health" ]] || { printf 'FAIL: health 命令没有进入健康巡检\n' >&2; exit 1; }

main updates
[[ "$captured" == "updates" ]] || { printf 'FAIL: updates 命令没有进入更新清单\n' >&2; exit 1; }

main storage
[[ "$captured" == "storage" ]] || { printf 'FAIL: storage 命令没有进入存储诊断\n' >&2; exit 1; }

main swap
[[ "$captured" == "swap" ]] || { printf 'FAIL: swap 命令没有进入生命周期管理\n' >&2; exit 1; }

main users
[[ "$captured" == "users" ]] || { printf 'FAIL: users 命令没有进入账户中心\n' >&2; exit 1; }

main user deploy
[[ "$captured" == "user:deploy" ]] || { printf 'FAIL: user 命令没有进入账户详情\n' >&2; exit 1; }

main process 1234
[[ "$captured" == "process:1234" ]] || { printf 'FAIL: process 命令没有进入进程详情\n' >&2; exit 1; }

if (main user '../root' >/dev/null 2>&1) || (main process '1;reboot' >/dev/null 2>&1); then
  printf 'FAIL: CLI 接受了危险账户名或 PID\n' >&2
  exit 1
fi

main logs nginx.service
[[ "$captured" == "logs:nginx.service" ]] || { printf 'FAIL: logs 命令没有读取指定服务\n' >&2; exit 1; }

main service nginx.service
[[ "$captured" == "service:nginx.service" ]] || { printf 'FAIL: service 命令没有打开服务管理\n' >&2; exit 1; }

main service nginx.service restart
[[ "$captured" == "service:nginx.service:restart" ]] || { printf 'FAIL: service 生命周期动作分发错误\n' >&2; exit 1; }

main timer apt-daily.timer
[[ "$captured" == "timer:apt-daily.timer" ]] || { printf 'FAIL: timer 命令没有进入 Timer 管理\n' >&2; exit 1; }

main journal
[[ "$captured" == "journal" ]] || { printf 'FAIL: journal 命令没有进入日志管理\n' >&2; exit 1; }

main compose edge-proxy
[[ "$captured" == "compose:edge-proxy" ]] || { printf 'FAIL: compose 命令没有进入项目管理\n' >&2; exit 1; }

if (main logs '../nginx' >/dev/null 2>&1); then
  printf 'FAIL: logs 接受了危险服务名\n' >&2
  exit 1
fi

main uninstall
[[ "$captured" == "uninstall" ]] || { printf 'FAIL: uninstall 命令没有进入卸载流程\n' >&2; exit 1; }

printf 'PASS: cli\n'
